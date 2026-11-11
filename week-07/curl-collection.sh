#!/usr/bin/env bash
# Runnable curl collection for the deployed HTTP API.
set -euo pipefail
BASE_URL="${BASE_URL:?Set BASE_URL to the API Gateway ApiEndpoint}"
BASE_URL="${BASE_URL%/}"
tmp=$(mktemp)
trap 'rm -f -- "$tmp"' EXIT

status=$(curl --silent --show-error --output "$tmp" --write-out '%{http_code}' \
  "$BASE_URL/properties/R100234")
python3 - "$tmp" "$status" <<'PY'
import json, sys
body = json.load(open(sys.argv[1], encoding="utf-8"))
assert sys.argv[2] == "200", (sys.argv[2], body)
assert body["L_ListingID"] == "R100234", body
assert body["L_City"] == "Sacramento", body
print("GET /properties/R100234 -> 200", json.dumps(body))
PY

status=$(curl --silent --show-error --output "$tmp" --write-out '%{http_code}' \
  "$BASE_URL/properties/DOES-NOT-EXIST")
python3 - "$tmp" "$status" <<'PY'
import json, sys
body = json.load(open(sys.argv[1], encoding="utf-8"))
assert sys.argv[2] == "404", (sys.argv[2], body)
assert body == {"error": "not found"}, body
print("GET /properties/DOES-NOT-EXIST -> 404", json.dumps(body))
PY
