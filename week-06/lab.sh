#!/usr/bin/env bash
# Reproducible Week 6 lab in us-east-2. Run from Ubuntu WSL with an AWS CLI profile.
set -euo pipefail
export AWS_PAGER=""
REGION=us-east-2
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE="$HERE/.lab-state"

record() { printf '%s=%q\n' "$1" "$2" >> "$STATE"; }
load_state() { [[ -f "$STATE" ]] || { echo "Missing $STATE" >&2; exit 1; }; source "$STATE"; }
tag_name() { aws ec2 create-tags --region "$REGION" --resources "$1" --tags "Key=Name,Value=$2"; }

deploy() {
  [[ ! -e "$STATE" ]] || { echo "Existing lab state: $STATE" >&2; exit 1; }
  umask 077
  : > "$STATE"
  record STARTED_UTC "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  record REGION "$REGION"

  local vpc igw pub_a pub_b priv_a priv_b pub_rt priv_rt eip nat
  local alb_sg instance_sg role profile template version tg alb listener asg
  local ami user_data
  ami=$(aws ec2 describe-launch-template-versions --region "$REGION" \
    --launch-template-name property-api-template --versions 1 \
    --query 'LaunchTemplateVersions[0].LaunchTemplateData.ImageId' --output text)
  [[ "$ami" != None ]]
  record AMI "$ami"

  vpc=$(aws ec2 create-vpc --region "$REGION" --cidr-block 10.0.0.0/16 \
    --query 'Vpc.VpcId' --output text)
  record VPC "$vpc"; tag_name "$vpc" training-vpc
  aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$vpc" --enable-dns-support '{"Value":true}'
  aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$vpc" --enable-dns-hostnames '{"Value":true}'
  igw=$(aws ec2 create-internet-gateway --region "$REGION" --query 'InternetGateway.InternetGatewayId' --output text)
  record IGW "$igw"; tag_name "$igw" training-igw
  aws ec2 attach-internet-gateway --region "$REGION" --vpc-id "$vpc" --internet-gateway-id "$igw"

  pub_a=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$vpc" --availability-zone us-east-2a --cidr-block 10.0.0.0/20 --query 'Subnet.SubnetId' --output text)
  record PUB_A "$pub_a"; tag_name "$pub_a" training-public-a
  pub_b=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$vpc" --availability-zone us-east-2b --cidr-block 10.0.16.0/20 --query 'Subnet.SubnetId' --output text)
  record PUB_B "$pub_b"; tag_name "$pub_b" training-public-b
  priv_a=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$vpc" --availability-zone us-east-2a --cidr-block 10.0.128.0/20 --query 'Subnet.SubnetId' --output text)
  record PRIV_A "$priv_a"; tag_name "$priv_a" training-private-a
  priv_b=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$vpc" --availability-zone us-east-2b --cidr-block 10.0.144.0/20 --query 'Subnet.SubnetId' --output text)
  record PRIV_B "$priv_b"; tag_name "$priv_b" training-private-b

  pub_rt=$(aws ec2 create-route-table --region "$REGION" --vpc-id "$vpc" --query 'RouteTable.RouteTableId' --output text)
  record PUB_RT "$pub_rt"; tag_name "$pub_rt" training-public-rt
  aws ec2 create-route --region "$REGION" --route-table-id "$pub_rt" --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw" >/dev/null
  aws ec2 associate-route-table --region "$REGION" --route-table-id "$pub_rt" --subnet-id "$pub_a" >/dev/null
  aws ec2 associate-route-table --region "$REGION" --route-table-id "$pub_rt" --subnet-id "$pub_b" >/dev/null

  eip=$(aws ec2 allocate-address --region "$REGION" --domain vpc --query 'AllocationId' --output text)
  record EIP "$eip"
  nat=$(aws ec2 create-nat-gateway --region "$REGION" --subnet-id "$pub_a" --allocation-id "$eip" --query 'NatGateway.NatGatewayId' --output text)
  record NAT "$nat"
  echo "Waiting for NAT gateway $nat"
  aws ec2 wait nat-gateway-available --region "$REGION" --nat-gateway-ids "$nat"
  priv_rt=$(aws ec2 create-route-table --region "$REGION" --vpc-id "$vpc" --query 'RouteTable.RouteTableId' --output text)
  record PRIV_RT "$priv_rt"; tag_name "$priv_rt" training-private-rt
  aws ec2 create-route --region "$REGION" --route-table-id "$priv_rt" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$nat" >/dev/null
  aws ec2 associate-route-table --region "$REGION" --route-table-id "$priv_rt" --subnet-id "$priv_a" >/dev/null
  aws ec2 associate-route-table --region "$REGION" --route-table-id "$priv_rt" --subnet-id "$priv_b" >/dev/null

  alb_sg=$(aws ec2 create-security-group --region "$REGION" --group-name property-api-week6-alb --description 'Week 6 ALB HTTP' --vpc-id "$vpc" --query 'GroupId' --output text)
  record ALB_SG "$alb_sg"
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$alb_sg" --protocol tcp --port 80 --cidr 0.0.0.0/0
  instance_sg=$(aws ec2 create-security-group --region "$REGION" --group-name property-api-week6-instance --description 'Week 6 targets from ALB only' --vpc-id "$vpc" --query 'GroupId' --output text)
  record INSTANCE_SG "$instance_sg"
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$instance_sg" --protocol tcp --port 8080 --source-group "$alb_sg"

  role=property-api-week6-ssm-role
  profile=property-api-week6-ssm-profile
  aws iam create-role --role-name "$role" --assume-role-policy-document "file://$HERE/ssm-trust.json" >/dev/null
  record ROLE "$role"
  aws iam attach-role-policy --role-name "$role" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  aws iam create-instance-profile --instance-profile-name "$profile" >/dev/null
  record PROFILE "$profile"
  aws iam add-role-to-instance-profile --instance-profile-name "$profile" --role-name "$role"
  sleep 15

  template=$(aws ec2 describe-launch-templates --region "$REGION" --launch-template-names property-api-template --query 'LaunchTemplates[0].LaunchTemplateId' --output text)
  record TEMPLATE "$template"
  user_data=$(base64 -w 0 "$HERE/../propertylite/ec2-user-data.sh")
  python3 - "$ami" "$instance_sg" "$profile" "$user_data" > "$HERE/.launch-data.json" <<'PY'
import json,sys
ami,sg,profile,user_data=sys.argv[1:]
json.dump({"ImageId":ami,"InstanceType":"t3.micro","SecurityGroupIds":[sg],"IamInstanceProfile":{"Name":profile},"Monitoring":{"Enabled":True},"UserData":user_data},sys.stdout)
PY
  version=$(aws ec2 create-launch-template-version --region "$REGION" --launch-template-id "$template" --source-version 1 --version-description 'Week 6 training-vpc PropertyLite bootstrap and SSM' --launch-template-data "file://$HERE/.launch-data.json" --query 'LaunchTemplateVersion.VersionNumber' --output text)
  record TEMPLATE_VERSION "$version"
  rm -f "$HERE/.launch-data.json"

  tg=$(aws elbv2 create-target-group --region "$REGION" --name property-api-week6-tg --protocol HTTP --port 8080 --vpc-id "$vpc" --target-type instance --health-check-protocol HTTP --health-check-path /health --matcher HttpCode=200 --query 'TargetGroups[0].TargetGroupArn' --output text)
  record TARGET_GROUP "$tg"
  alb=$(aws elbv2 create-load-balancer --region "$REGION" --name property-api-week6-alb --type application --scheme internet-facing --ip-address-type ipv4 --security-groups "$alb_sg" --subnets "$pub_a" "$pub_b" --query 'LoadBalancers[0].LoadBalancerArn' --output text)
  record ALB "$alb"
  aws elbv2 wait load-balancer-available --region "$REGION" --load-balancer-arns "$alb"
  listener=$(aws elbv2 create-listener --region "$REGION" --load-balancer-arn "$alb" --protocol HTTP --port 80 --default-actions "Type=forward,TargetGroupArn=$tg" --query 'Listeners[0].ListenerArn' --output text)
  record LISTENER "$listener"

  asg=property-api-week6-asg
  aws autoscaling create-auto-scaling-group --region "$REGION" --auto-scaling-group-name "$asg" --launch-template "LaunchTemplateId=$template,Version=$version" --vpc-zone-identifier "$priv_a,$priv_b" --target-group-arns "$tg" --min-size 1 --max-size 4 --desired-capacity 2 --health-check-type ELB --health-check-grace-period 300 --default-instance-warmup 120 --tags "ResourceId=$asg,ResourceType=auto-scaling-group,Key=Name,Value=property-api-week6-instance,PropagateAtLaunch=true"
  record ASG "$asg"
  set_policy
  aws autoscaling enable-metrics-collection --region "$REGION" --auto-scaling-group-name "$asg" --granularity 1Minute
  echo "Deployed VPC=$vpc ALB=$alb ASG=$asg template version=$version"
}

set_policy() {
  load_state
  local attempt
  for attempt in 1 2 3 4 5 6; do
    if aws autoscaling put-scaling-policy --region "$REGION" --auto-scaling-group-name "$ASG" --policy-name property-api-week6-cpu50 --policy-type TargetTrackingScaling --target-tracking-configuration '{"PredefinedMetricSpecification":{"PredefinedMetricType":"ASGAverageCPUUtilization"},"TargetValue":50.0}' >/dev/null; then
      record POLICY property-api-week6-cpu50
      echo "CPU target tracking policy attached"
      return
    fi
    echo "Policy attempt $attempt failed; waiting for AWS service-linked role" >&2
    sleep 15
  done
  return 1
}

status() {
  load_state
  aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:Instances[].{Id:InstanceId,Lifecycle:LifecycleState,Health:HealthStatus}}' --output json
  aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TARGET_GROUP" --query 'TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}' --output json
  aws elbv2 describe-load-balancers --region "$REGION" --load-balancer-arns "$ALB" --query 'LoadBalancers[0].DNSName' --output text
}

verify() {
  load_state
  local dns
  aws elbv2 wait target-in-service --region "$REGION" --target-group-arn "$TARGET_GROUP"
  dns=$(aws elbv2 describe-load-balancers --region "$REGION" --load-balancer-arns "$ALB" --query 'LoadBalancers[0].DNSName' --output text)
  echo "Health response:"
  curl -fsS --max-time 20 "http://$dns/health"
  echo
  echo "Listings response:"
  curl -fsS --max-time 20 "http://$dns/properties"
  echo
  aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TARGET_GROUP" --query 'TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State}' --output json
}

self_heal() {
  load_state
  local old
  old=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)
  [[ "$old" == i-* ]]
  record SELF_HEAL_OLD "$old"
  record SELF_HEAL_START_UTC "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  aws ec2 terminate-instances --region "$REGION" --instance-ids "$old" --query 'TerminatingInstances[0].{Id:InstanceId,State:CurrentState.Name}' --output json
}

stress() {
  load_state
  local ids command_id
  mapfile -t ids < <(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' --output text | tr '\t' '\n')
  [[ "${#ids[@]}" -eq 2 ]] || { echo "Expected two InService instances, got ${#ids[@]}" >&2; exit 1; }
  record STRESS_INSTANCES "${ids[*]}"
  record STRESS_START_UTC "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  command_id=$(aws ssm send-command --region "$REGION" --instance-ids "${ids[@]}" --document-name AWS-RunShellScript --comment 'Week 6 CPU target tracking scale-out test' --parameters '{"commands":["sudo dnf install -y stress-ng","stress-ng --cpu 2 --timeout 600s"],"executionTimeout":["660"]}' --timeout-seconds 660 --query 'Command.CommandId' --output text)
  record STRESS_COMMAND "$command_id"
  echo "Started stress command $command_id on ${ids[*]}"
}

diagnose() {
  load_state
  local instance_id="${2:?instance ID required}" command_id
  command_id=$(aws ssm send-command --region "$REGION" --instance-ids "$instance_id" --document-name AWS-RunShellScript --parameters '{"commands":["cloud-init status || true","systemctl is-active propertylite || true","curl -sS -o /dev/null -w HTTP_%{http_code} http://localhost:8080/health || true","tail -n 12 /var/log/cloud-init-output.log"]}' --query 'Command.CommandId' --output text)
  sleep 5
  aws ssm get-command-invocation --region "$REGION" --command-id "$command_id" --instance-id "$instance_id" --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' --output json
}

cleanup() {
  load_state
  [[ "$VPC" == vpc-* && "$ASG" == property-api-week6-asg && "$ALB" == arn:aws:elasticloadbalancing:* ]] || { echo 'Unexpected lab state; refusing cleanup' >&2; exit 1; }
  local ids association nat_state attempt
  if [[ "$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$ASG" --query 'length(AutoScalingGroups)' --output text)" != 0 ]]; then
    mapfile -t ids < <(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].Instances[].InstanceId' --output text | tr '\t' '\n' | grep '^i-' || true)
    echo "Deleting ASG and terminating ${#ids[@]} instances"
    aws autoscaling delete-auto-scaling-group --region "$REGION" --auto-scaling-group-name "$ASG" --force-delete
    for attempt in $(seq 1 60); do
      [[ "$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$ASG" --query 'length(AutoScalingGroups)' --output text)" == 0 ]] && break
      sleep 15
    done
    [[ "$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$ASG" --query 'length(AutoScalingGroups)' --output text)" == 0 ]]
    if [[ "${#ids[@]}" -gt 0 ]]; then
      aws ec2 wait instance-terminated --region "$REGION" --instance-ids "${ids[@]}"
    fi
  fi

  echo 'Deleting ALB, target group, and launch template'
  if aws elbv2 describe-load-balancers --region "$REGION" --load-balancer-arns "$ALB" >/dev/null 2>&1; then
    aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$ALB"
    aws elbv2 wait load-balancers-deleted --region "$REGION" --load-balancer-arns "$ALB"
  fi
  for attempt in $(seq 1 20); do
    if aws elbv2 delete-target-group --region "$REGION" --target-group-arn "$TARGET_GROUP"; then break; fi
    echo 'Waiting for target group listener reference to clear' >&2
    sleep 10
  done
  if aws elbv2 describe-target-groups --region "$REGION" --target-group-arns "$TARGET_GROUP" >/dev/null 2>&1; then
    echo 'Target group was not deleted' >&2; exit 1
  fi
  aws ec2 delete-launch-template --region "$REGION" --launch-template-id "$TEMPLATE" >/dev/null

  echo 'Deleting lab instance profile and role'
  aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE" --role-name "$ROLE"
  aws iam delete-instance-profile --instance-profile-name "$PROFILE"
  aws iam detach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  aws iam delete-role --role-name "$ROLE"

  echo 'Deleting NAT gateway and VPC network resources'
  aws ec2 delete-nat-gateway --region "$REGION" --nat-gateway-id "$NAT" >/dev/null
  for attempt in $(seq 1 80); do
    nat_state=$(aws ec2 describe-nat-gateways --region "$REGION" --nat-gateway-ids "$NAT" --query 'NatGateways[0].State' --output text 2>/dev/null || true)
    [[ "$nat_state" == deleted || "$nat_state" == None || -z "$nat_state" ]] && break
    sleep 15
  done
  [[ "$nat_state" == deleted || "$nat_state" == None || -z "$nat_state" ]]
  aws ec2 release-address --region "$REGION" --allocation-id "$EIP"
  aws ec2 delete-security-group --region "$REGION" --group-id "$INSTANCE_SG"
  aws ec2 delete-security-group --region "$REGION" --group-id "$ALB_SG"
  for association in $(aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$PUB_RT" "$PRIV_RT" --query 'RouteTables[].Associations[].RouteTableAssociationId' --output text); do
    aws ec2 disassociate-route-table --region "$REGION" --association-id "$association"
  done
  aws ec2 delete-route-table --region "$REGION" --route-table-id "$PRIV_RT"
  aws ec2 delete-route-table --region "$REGION" --route-table-id "$PUB_RT"
  aws ec2 delete-subnet --region "$REGION" --subnet-id "$PRIV_A"
  aws ec2 delete-subnet --region "$REGION" --subnet-id "$PRIV_B"
  aws ec2 delete-subnet --region "$REGION" --subnet-id "$PUB_A"
  aws ec2 delete-subnet --region "$REGION" --subnet-id "$PUB_B"
  aws ec2 detach-internet-gateway --region "$REGION" --internet-gateway-id "$IGW" --vpc-id "$VPC"
  aws ec2 delete-internet-gateway --region "$REGION" --internet-gateway-id "$IGW"
  aws ec2 delete-vpc --region "$REGION" --vpc-id "$VPC"
  record CLEANUP_UTC "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo 'Week 6 lab resources deleted'
}

case "${1:-}" in
  deploy) deploy ;;
  policy) set_policy ;;
  status) status ;;
  verify) verify ;;
  self-heal) self_heal ;;
  stress) stress ;;
  diagnose) diagnose "$@" ;;
  cleanup) cleanup ;;
  *) echo "Usage: bash week-06/lab.sh {deploy|policy|status|verify|self-heal|stress|diagnose INSTANCE_ID|cleanup}" >&2; exit 2 ;;
esac
