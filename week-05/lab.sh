#!/usr/bin/env bash
# Week 5 disposable networking lab. Run from Ubuntu WSL with an AWS CLI profile.
set -euo pipefail
export AWS_PAGER=""
REGION=us-east-2
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE="$HERE/.lab-state"

record() {
  printf '%s=%q\n' "$1" "$2" >> "$STATE"
}

load_state() {
  if [[ ! -f "$STATE" ]]; then
    echo "No Week 5 lab state at $STATE" >&2
    exit 1
  fi
  # The state file is created only by this script and has owner-only permissions.
  source "$STATE"
}

tag_name() {
  aws ec2 create-tags --region "$REGION" --resources "$1" \
    --tags "Key=Name,Value=$2"
}

deploy() {
  if [[ -e "$STATE" ]]; then
    echo "An existing lab state file must be cleaned up first: $STATE" >&2
    exit 1
  fi
  umask 077
  : > "$STATE"
  record STARTED_UTC "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  record REGION "$REGION"

  local az_a az_b ip ami
  az_a=$(aws ec2 describe-availability-zones --region "$REGION" \
    --query 'AvailabilityZones[0].ZoneName' --output text)
  az_b=$(aws ec2 describe-availability-zones --region "$REGION" \
    --query 'AvailabilityZones[1].ZoneName' --output text)
  [[ "$az_a" != "$az_b" && "$az_a" != None && "$az_b" != None ]]
  record AZ_A "$az_a"
  record AZ_B "$az_b"

  local vpc igw pub_a pub_b priv_a priv_b pub_rt priv_rt pub_assoc_a pub_assoc_b
  local priv_assoc_a priv_assoc_b eip_alloc nat bastion_sg private_sg key_name key_path
  local bastion_instance private_instance

  vpc=$(aws ec2 create-vpc --region "$REGION" --cidr-block 10.0.0.0/16 \
    --query 'Vpc.VpcId' --output text)
  record VPC "$vpc"
  tag_name "$vpc" training-vpc
  aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$vpc" \
    --enable-dns-support '{"Value":true}'
  aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$vpc" \
    --enable-dns-hostnames '{"Value":true}'

  igw=$(aws ec2 create-internet-gateway --region "$REGION" \
    --query 'InternetGateway.InternetGatewayId' --output text)
  record IGW "$igw"
  tag_name "$igw" training-igw
  aws ec2 attach-internet-gateway --region "$REGION" --vpc-id "$vpc" \
    --internet-gateway-id "$igw"

  pub_a=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$vpc" \
    --availability-zone "$az_a" --cidr-block 10.0.0.0/20 \
    --query 'Subnet.SubnetId' --output text)
  record PUB_A "$pub_a"
  tag_name "$pub_a" training-public-a
  pub_b=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$vpc" \
    --availability-zone "$az_b" --cidr-block 10.0.16.0/20 \
    --query 'Subnet.SubnetId' --output text)
  record PUB_B "$pub_b"
  tag_name "$pub_b" training-public-b
  priv_a=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$vpc" \
    --availability-zone "$az_a" --cidr-block 10.0.128.0/20 \
    --query 'Subnet.SubnetId' --output text)
  record PRIV_A "$priv_a"
  tag_name "$priv_a" training-private-a
  priv_b=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$vpc" \
    --availability-zone "$az_b" --cidr-block 10.0.144.0/20 \
    --query 'Subnet.SubnetId' --output text)
  record PRIV_B "$priv_b"
  tag_name "$priv_b" training-private-b

  pub_rt=$(aws ec2 create-route-table --region "$REGION" --vpc-id "$vpc" \
    --query 'RouteTable.RouteTableId' --output text)
  record PUB_RT "$pub_rt"
  tag_name "$pub_rt" training-public-rt
  aws ec2 create-route --region "$REGION" --route-table-id "$pub_rt" \
    --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw" >/dev/null
  pub_assoc_a=$(aws ec2 associate-route-table --region "$REGION" \
    --route-table-id "$pub_rt" --subnet-id "$pub_a" \
    --query 'AssociationId' --output text)
  record PUB_ASSOC_A "$pub_assoc_a"
  pub_assoc_b=$(aws ec2 associate-route-table --region "$REGION" \
    --route-table-id "$pub_rt" --subnet-id "$pub_b" \
    --query 'AssociationId' --output text)
  record PUB_ASSOC_B "$pub_assoc_b"

  eip_alloc=$(aws ec2 allocate-address --region "$REGION" --domain vpc \
    --query 'AllocationId' --output text)
  record EIP_ALLOC "$eip_alloc"
  nat=$(aws ec2 create-nat-gateway --region "$REGION" --subnet-id "$pub_a" \
    --allocation-id "$eip_alloc" --query 'NatGateway.NatGatewayId' --output text)
  record NAT "$nat"
  echo "Waiting for NAT gateway $nat ..."
  aws ec2 wait nat-gateway-available --region "$REGION" --nat-gateway-ids "$nat"

  priv_rt=$(aws ec2 create-route-table --region "$REGION" --vpc-id "$vpc" \
    --query 'RouteTable.RouteTableId' --output text)
  record PRIV_RT "$priv_rt"
  tag_name "$priv_rt" training-private-rt
  aws ec2 create-route --region "$REGION" --route-table-id "$priv_rt" \
    --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$nat" >/dev/null
  priv_assoc_a=$(aws ec2 associate-route-table --region "$REGION" \
    --route-table-id "$priv_rt" --subnet-id "$priv_a" \
    --query 'AssociationId' --output text)
  record PRIV_ASSOC_A "$priv_assoc_a"
  priv_assoc_b=$(aws ec2 associate-route-table --region "$REGION" \
    --route-table-id "$priv_rt" --subnet-id "$priv_b" \
    --query 'AssociationId' --output text)
  record PRIV_ASSOC_B "$priv_assoc_b"

  ip=$(curl -4fsS https://checkip.amazonaws.com | tr -d '\r\n')
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
  record SOURCE_IP "$ip"
  bastion_sg=$(aws ec2 create-security-group --region "$REGION" \
    --group-name "training-week5-bastion-$(date -u +%Y%m%d%H%M%S)" \
    --description 'Week 5 bastion SSH from current IP' --vpc-id "$vpc" \
    --query 'GroupId' --output text)
  record BASTION_SG "$bastion_sg"
  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$bastion_sg" --protocol tcp --port 22 --cidr "$ip/32"
  private_sg=$(aws ec2 create-security-group --region "$REGION" \
    --group-name "training-week5-private-$(date -u +%Y%m%d%H%M%S)" \
    --description 'Week 5 private SSH only from bastion SG' --vpc-id "$vpc" \
    --query 'GroupId' --output text)
  record PRIVATE_SG "$private_sg"
  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$private_sg" --protocol tcp --port 22 \
    --source-group "$bastion_sg"

  key_name="idx-week5-$(date -u +%Y%m%d%H%M%S)"
  key_path="$HOME/.ssh/$key_name.pem"
  mkdir -p "$HOME/.ssh"
  [[ ! -e "$key_path" ]]
  aws ec2 create-key-pair --region "$REGION" --key-name "$key_name" \
    --key-type rsa --key-format pem --query 'KeyMaterial' --output text > "$key_path"
  chmod 600 "$key_path"
  record KEY_NAME "$key_name"
  record KEY_PATH "$key_path"

  ami=$(aws ssm get-parameter --region "$REGION" \
    --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
    --query 'Parameter.Value' --output text)
  record AMI "$ami"
  bastion_instance=$(aws ec2 run-instances --region "$REGION" --image-id "$ami" \
    --instance-type t3.micro --key-name "$key_name" --subnet-id "$pub_a" \
    --security-group-ids "$bastion_sg" --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=training-week5-bastion}]' \
    --query 'Instances[0].InstanceId' --output text)
  record BASTION_INSTANCE "$bastion_instance"
  private_instance=$(aws ec2 run-instances --region "$REGION" --image-id "$ami" \
    --instance-type t3.micro --key-name "$key_name" --subnet-id "$priv_a" \
    --security-group-ids "$private_sg" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=training-week5-private}]' \
    --query 'Instances[0].InstanceId' --output text)
  record PRIVATE_INSTANCE "$private_instance"
  echo "Created VPC $vpc, NAT $nat, bastion $bastion_instance, private $private_instance"
  echo "Run: bash week-05/lab.sh verify"
}

verify() {
  load_state
  local bastion_ip private_ip private_public state nat_state pub_route priv_route
  aws ec2 wait instance-status-ok --region "$REGION" \
    --instance-ids "$BASTION_INSTANCE" "$PRIVATE_INSTANCE"
  bastion_ip=$(aws ec2 describe-instances --region "$REGION" \
    --instance-ids "$BASTION_INSTANCE" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
  private_ip=$(aws ec2 describe-instances --region "$REGION" \
    --instance-ids "$PRIVATE_INSTANCE" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
  private_public=$(aws ec2 describe-instances --region "$REGION" \
    --instance-ids "$PRIVATE_INSTANCE" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
  [[ "$bastion_ip" != None && "$private_ip" != None && "$private_public" == None ]]
  nat_state=$(aws ec2 describe-nat-gateways --region "$REGION" \
    --nat-gateway-ids "$NAT" --query 'NatGateways[0].State' --output text)
  [[ "$nat_state" == available ]]
  pub_route=$(aws ec2 describe-route-tables --region "$REGION" \
    --route-table-ids "$PUB_RT" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId|[0]' --output text)
  priv_route=$(aws ec2 describe-route-tables --region "$REGION" \
    --route-table-ids "$PRIV_RT" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].NatGatewayId|[0]' --output text)
  [[ "$pub_route" == "$IGW" && "$priv_route" == "$NAT" ]]
  echo "VPC=$VPC AZs=$AZ_A,$AZ_B"
  echo "Public route: 0.0.0.0/0 -> $pub_route; associated with $PUB_A and $PUB_B"
  echo "Private route: 0.0.0.0/0 -> $priv_route; associated with $PRIV_A and $PRIV_B"
  echo "NAT=$nat_state; bastion public IP=$bastion_ip; private IP=$private_ip; private public IP=$private_public"

  eval "$(ssh-agent -s)" >/dev/null
  trap 'kill "$SSH_AGENT_PID" 2>/dev/null || true' EXIT
  ssh-add "$KEY_PATH" >/dev/null
  ssh -A -T -i "$KEY_PATH" -o BatchMode=yes -o ConnectTimeout=20 \
    -o StrictHostKeyChecking=accept-new "ec2-user@$bastion_ip" \
    "ssh -T -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new ec2-user@$private_ip bash -s" <<'REMOTE'
set -e
printf 'HOP_OK\n'
printf 'PRIVATE_HOST=%s\n' "$(hostname)"
curl -4fsS --max-time 20 https://checkip.amazonaws.com | sed 's/^/NAT_EGRESS_IP=/'
sudo yum update -y > /tmp/week5-yum-update.log 2>&1
printf 'YUM_UPDATE_OK\n'
REMOTE
  echo "Verified at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

cleanup() {
  load_state
  local instance_ids=() id nat_state
  [[ -n "${BASTION_INSTANCE:-}" ]] && instance_ids+=("$BASTION_INSTANCE")
  [[ -n "${PRIVATE_INSTANCE:-}" ]] && instance_ids+=("$PRIVATE_INSTANCE")
  if ((${#instance_ids[@]})); then
    aws ec2 terminate-instances --region "$REGION" --instance-ids "${instance_ids[@]}" >/dev/null
    aws ec2 wait instance-terminated --region "$REGION" --instance-ids "${instance_ids[@]}"
  fi
  if [[ -n "${NAT:-}" ]]; then
    aws ec2 delete-nat-gateway --region "$REGION" --nat-gateway-id "$NAT" >/dev/null
    for ((i=0; i<80; i++)); do
      nat_state=$(aws ec2 describe-nat-gateways --region "$REGION" \
        --nat-gateway-ids "$NAT" --query 'NatGateways[0].State' \
        --output text 2>/dev/null || echo deleted)
      [[ "$nat_state" == deleted || "$nat_state" == None ]] && break
      sleep 10
    done
    [[ "$nat_state" == deleted || "$nat_state" == None ]]
  fi
  [[ -n "${PRIVATE_SG:-}" ]] && aws ec2 delete-security-group --region "$REGION" --group-id "$PRIVATE_SG"
  [[ -n "${BASTION_SG:-}" ]] && aws ec2 delete-security-group --region "$REGION" --group-id "$BASTION_SG"
  for id in "${PRIV_ASSOC_A:-}" "${PRIV_ASSOC_B:-}" "${PUB_ASSOC_A:-}" "${PUB_ASSOC_B:-}"; do
    [[ -n "$id" ]] && aws ec2 disassociate-route-table --region "$REGION" --association-id "$id"
  done
  [[ -n "${PRIV_RT:-}" ]] && aws ec2 delete-route-table --region "$REGION" --route-table-id "$PRIV_RT"
  [[ -n "${PUB_RT:-}" ]] && aws ec2 delete-route-table --region "$REGION" --route-table-id "$PUB_RT"
  [[ -n "${EIP_ALLOC:-}" ]] && aws ec2 release-address --region "$REGION" --allocation-id "$EIP_ALLOC"
  if [[ -n "${IGW:-}" ]]; then
    aws ec2 detach-internet-gateway --region "$REGION" --internet-gateway-id "$IGW" --vpc-id "$VPC"
    aws ec2 delete-internet-gateway --region "$REGION" --internet-gateway-id "$IGW"
  fi
  for id in "${PRIV_A:-}" "${PRIV_B:-}" "${PUB_A:-}" "${PUB_B:-}"; do
    [[ -n "$id" ]] && aws ec2 delete-subnet --region "$REGION" --subnet-id "$id"
  done
  [[ -n "${VPC:-}" ]] && aws ec2 delete-vpc --region "$REGION" --vpc-id "$VPC"
  [[ -n "${KEY_NAME:-}" ]] && aws ec2 delete-key-pair --region "$REGION" --key-name "$KEY_NAME"
  [[ -n "${KEY_PATH:-}" ]] && rm -f -- "$KEY_PATH"
  echo "Removed Week 5 lab resources at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  rm -f -- "$STATE"
}

case "${1:-}" in
  deploy) deploy ;;
  verify) verify ;;
  cleanup) cleanup ;;
  *) echo 'Usage: bash week-05/lab.sh {deploy|verify|cleanup}' >&2; exit 2 ;;
esac
