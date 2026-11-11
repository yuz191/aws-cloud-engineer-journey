#!/usr/bin/env bash
# Disposable Week 7 AWS lab. Run in Ubuntu WSL with an authenticated AWS CLI.
set -euo pipefail
export AWS_PAGER=""
REGION="${AWS_REGION:-us-east-2}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE="$HERE/.lab-state"
ROLE_NAME=propertylite-week7-get-property
FUNCTION_NAME=propertylite-week7-get-property
API_NAME=propertylite-week7
TABLE_NAME=Properties
DLQ_NAME=property-dlq-week7
QUEUE_NAME=property-queue-week7

record() { printf '%s=%q\n' "$1" "$2" >> "$STATE"; }
load_state() { [[ -f "$STATE" ]] || { echo "Missing $STATE" >&2; exit 1; }; source "$STATE"; }

deploy() {
  [[ ! -e "$STATE" ]] || { echo "Existing lab state: $STATE" >&2; exit 1; }
  for name in "$DLQ_NAME" "$QUEUE_NAME"; do
    if aws sqs get-queue-url --queue-name "$name" --region "$REGION" >/dev/null 2>&1; then
      echo "Queue $name already exists; refusing to reuse it" >&2; exit 1
    fi
  done
  if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo "Table $TABLE_NAME already exists; refusing to reuse it" >&2; exit 1
  fi
  if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    echo "Role $ROLE_NAME already exists; refusing to reuse it" >&2; exit 1
  fi
  if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo "Function $FUNCTION_NAME already exists; refusing to reuse it" >&2; exit 1
  fi

  local account tmp role_arn function_arn integration endpoint dlq_arn redrive
  account=$(aws sts get-caller-identity --query Account --output text)
  umask 077
  : > "$STATE"
  record REGION "$REGION"
  record ACCOUNT "$account"
  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' RETURN

  aws dynamodb create-table --region "$REGION" --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=L_ListingID,AttributeType=S \
    --key-schema AttributeName=L_ListingID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  record TABLE "$TABLE_NAME"
  aws dynamodb wait table-exists --region "$REGION" --table-name "$TABLE_NAME"
  python3 "$HERE/seed_table.py" --region "$REGION"

  cat > "$tmp/trust.json" <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
  role_arn=$(aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://$tmp/trust.json" --query Role.Arn --output text)
  record ROLE "$ROLE_NAME"
  aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  printf '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["dynamodb:GetItem"],"Resource":"arn:aws:dynamodb:%s:%s:table/%s"}]}' \
    "$REGION" "$account" "$TABLE_NAME" > "$tmp/read-policy.json"
  aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name PropertiesGetItemOnly \
    --policy-document "file://$tmp/read-policy.json"

  python3 - "$HERE/handler.py" "$tmp/lambda.zip" <<'PY'
import sys
from zipfile import ZipFile, ZIP_DEFLATED
with ZipFile(sys.argv[2], "w", ZIP_DEFLATED) as archive:
    archive.write(sys.argv[1], "handler.py")
PY
  # IAM propagation is eventually consistent; retry only this creation step.
  for attempt in 1 2 3 4 5; do
    if function_arn=$(aws lambda create-function --region "$REGION" \
      --function-name "$FUNCTION_NAME" --runtime python3.12 \
      --handler handler.lambda_handler --role "$role_arn" \
      --timeout 10 \
      --zip-file "fileb://$tmp/lambda.zip" \
      --environment "Variables={TABLE_NAME=$TABLE_NAME}" \
      --query FunctionArn --output text 2>"$tmp/lambda-error"); then break; fi
    if [[ $attempt == 5 ]]; then cat "$tmp/lambda-error" >&2; exit 1; fi
    sleep 5
  done
  record FUNCTION "$FUNCTION_NAME"
  aws lambda wait function-active-v2 --region "$REGION" --function-name "$FUNCTION_NAME"

  local api_id
  api_id=$(aws apigatewayv2 create-api --region "$REGION" --name "$API_NAME" \
    --protocol-type HTTP --query ApiId --output text)
  record API_ID "$api_id"
  integration=$(aws apigatewayv2 create-integration --region "$REGION" --api-id "$api_id" \
    --integration-type AWS_PROXY --integration-uri "$function_arn" \
    --payload-format-version 2.0 --query IntegrationId --output text)
  aws apigatewayv2 create-route --region "$REGION" --api-id "$api_id" \
    --route-key 'GET /properties/{id}' --target "integrations/$integration" >/dev/null
  aws apigatewayv2 create-stage --region "$REGION" --api-id "$api_id" \
    --stage-name '$default' --auto-deploy >/dev/null
  aws lambda add-permission --region "$REGION" --function-name "$FUNCTION_NAME" \
    --statement-id propertylite-week7-api --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$account:$api_id/*/GET/properties/*" >/dev/null
  endpoint=$(aws apigatewayv2 get-api --region "$REGION" --api-id "$api_id" \
    --query ApiEndpoint --output text)
  record API_URL "$endpoint"

  DLQ_URL=$(aws sqs create-queue --region "$REGION" --queue-name "$DLQ_NAME" \
    --query QueueUrl --output text)
  record DLQ_URL "$DLQ_URL"
  dlq_arn=$(aws sqs get-queue-attributes --region "$REGION" --queue-url "$DLQ_URL" \
    --attribute-names QueueArn --query Attributes.QueueArn --output text)
  redrive=$(python3 - "$dlq_arn" <<'PY'
import json, sys
print(json.dumps({"RedrivePolicy": json.dumps({"deadLetterTargetArn": sys.argv[1], "maxReceiveCount": "3"})}))
PY
)
  printf '%s' "$redrive" > "$tmp/sqs-attributes.json"
  QUEUE_URL=$(aws sqs create-queue --region "$REGION" --queue-name "$QUEUE_NAME" \
    --attributes "file://$tmp/sqs-attributes.json" --query QueueUrl --output text)
  record QUEUE_URL "$QUEUE_URL"
  echo "Deployed: $endpoint/properties/R100234"
  echo "Run: bash $HERE/lab.sh verify"
}

verify() {
  load_state
  BASE_URL="$API_URL" bash "$HERE/curl-collection.sh"
  local redrive message body receipt
  redrive=$(aws sqs get-queue-attributes --region "$REGION" --queue-url "$QUEUE_URL" \
    --attribute-names RedrivePolicy --query Attributes.RedrivePolicy --output text)
  python3 - "$redrive" <<'PY'
import json, sys
policy = json.loads(sys.argv[1])
assert int(policy["maxReceiveCount"]) == 3
assert policy["deadLetterTargetArn"].endswith(":property-dlq-week7")
print("SQS redrive policy: 3 receives -> property-dlq-week7")
PY
  aws sqs send-message --region "$REGION" --queue-url "$QUEUE_URL" \
    --message-body '{"PropertyId":"R100234"}' >/dev/null
  message=$(aws sqs receive-message --region "$REGION" --queue-url "$QUEUE_URL" \
    --wait-time-seconds 10 --output json)
  body=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["Messages"][0]["Body"])' <<< "$message")
  receipt=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["Messages"][0]["ReceiptHandle"])' <<< "$message")
  [[ "$body" == '{"PropertyId":"R100234"}' ]]
  echo "SQS received: $body"
  aws sqs delete-message --region "$REGION" --queue-url "$QUEUE_URL" \
    --receipt-handle "$receipt"
}

cleanup() {
  load_state
  if [[ -n "${API_ID:-}" ]]; then
    aws apigatewayv2 delete-api --region "$REGION" --api-id "$API_ID"
  fi
  if [[ -n "${FUNCTION:-}" ]]; then
    aws lambda delete-function --region "$REGION" --function-name "$FUNCTION"
    aws logs delete-log-group --region "$REGION" \
      --log-group-name "/aws/lambda/$FUNCTION"
  fi
  if [[ -n "${ROLE:-}" ]]; then
    aws iam detach-role-policy --role-name "$ROLE" \
      --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    aws iam delete-role-policy --role-name "$ROLE" --policy-name PropertiesGetItemOnly
    aws iam delete-role --role-name "$ROLE"
  fi
  if [[ -n "${QUEUE_URL:-}" ]]; then
    aws sqs delete-queue --region "$REGION" --queue-url "$QUEUE_URL"
  fi
  if [[ -n "${DLQ_URL:-}" ]]; then
    aws sqs delete-queue --region "$REGION" --queue-url "$DLQ_URL"
  fi
  if [[ -n "${TABLE:-}" ]]; then
    aws dynamodb delete-table --region "$REGION" --table-name "$TABLE" >/dev/null
    aws dynamodb wait table-not-exists --region "$REGION" --table-name "$TABLE"
  fi
  rm -- "$STATE"
  echo "Week 7 lab resources and Lambda log group deleted."
}

case "${1:-}" in
  deploy) deploy ;;
  verify) verify ;;
  cleanup) cleanup ;;
  *) echo "Usage: bash lab.sh {deploy|verify|cleanup}" >&2; exit 2 ;;
esac
