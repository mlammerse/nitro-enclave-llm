#!/usr/bin/env bash
# Provision the AWS foundation for a Nitro Enclave parent instance.
# Idempotent-ish: skips resources that already exist. Run from your Mac after
# `aws configure`. Costs money once the instance launches — you will be prompted.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# --- Pre-flight ---
say "Caller identity:"
aws sts get-caller-identity --region "$AWS_REGION" --output table

# --- Default VPC + a subnet ---
VPC_ID=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
  --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
[ "$VPC_ID" = "None" ] && { echo "No default VPC. Create one or set VPC_ID manually."; exit 1; }
SUBNET_ID=$(aws ec2 describe-subnets --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
  --query 'Subnets[0].SubnetId' --output text)
say "VPC=$VPC_ID  Subnet=$SUBNET_ID"

# --- Key pair (break-glass) ---
if ! aws ec2 describe-key-pairs --region "$AWS_REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
  say "Creating key pair $KEY_NAME -> ./${KEY_NAME}.pem"
  aws ec2 create-key-pair --region "$AWS_REGION" --key-name "$KEY_NAME" \
    --query 'KeyMaterial' --output text > "${KEY_NAME}.pem"
  chmod 600 "${KEY_NAME}.pem"
else
  say "Key pair $KEY_NAME exists, skipping."
fi

# --- IAM role + instance profile for SSM ---
if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  say "Creating IAM role $ROLE_NAME"
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME" >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME"
  say "Waiting for instance profile to propagate..."; sleep 12
else
  say "IAM role $ROLE_NAME exists, skipping."
fi

# --- Security group: NO inbound, egress allowed (yum + HF download) ---
if ! aws ec2 describe-security-groups --region "$AWS_REGION" \
     --filters Name=group-name,Values="$SG_NAME" Name=vpc-id,Values="$VPC_ID" \
     --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null | grep -q sg-; then
  say "Creating security group $SG_NAME (no inbound rules)"
  SG_ID=$(aws ec2 create-security-group --region "$AWS_REGION" \
    --group-name "$SG_NAME" --description "Nitro LLM enclave parent - SSM only, no inbound" \
    --vpc-id "$VPC_ID" --query 'GroupId' --output text)
else
  SG_ID=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
    --filters Name=group-name,Values="$SG_NAME" Name=vpc-id,Values="$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' --output text)
  say "Security group $SG_NAME exists ($SG_ID), skipping."
fi

# --- Latest Amazon Linux 2023 AMI (x86_64) via SSM public parameter ---
AMI_ID=$(aws ssm get-parameters --region "$AWS_REGION" \
  --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameters[0].Value' --output text)
say "AMI=$AMI_ID"

# --- Spend confirmation ---
echo
echo "About to launch a $INSTANCE_TYPE in $AWS_REGION (~US\$0.42/hr on-demand)."
read -r -p "Type 'launch' to proceed: " CONFIRM
[ "$CONFIRM" = "launch" ] || { echo "Aborted."; exit 1; }

# --- Launch enclave-enabled instance ---
say "Launching instance..."
INSTANCE_ID=$(aws ec2 run-instances --region "$AWS_REGION" \
  --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" --security-group-ids "$SG_ID" --subnet-id "$SUBNET_ID" \
  --iam-instance-profile "Name=$PROFILE_NAME" \
  --enclave-options 'Enabled=true' \
  --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":${VOLUME_GB},\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT}-parent},{Key=Project,Value=${PROJECT}}]" \
  --query 'Instances[0].InstanceId' --output text)

echo "$INSTANCE_ID" > .instance-id
say "Launched $INSTANCE_ID — waiting for running + SSM registration..."
aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$INSTANCE_ID"
say "Instance is running. SSM agent may take ~1-2 min more to register."
say "Connect with:  ./01-connect.sh"
