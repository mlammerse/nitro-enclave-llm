#!/usr/bin/env bash
# Remove all billable resources created by 00-bootstrap-aws.sh.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env
say() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }

INSTANCE_ID="$(cat .instance-id 2>/dev/null || true)"
if [ -n "$INSTANCE_ID" ]; then
  say "Terminating instance $INSTANCE_ID"
  aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" >/dev/null || true
  aws ec2 wait instance-terminated --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" || true
  rm -f .instance-id
fi

say "Detaching + deleting IAM role/profile"
aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME" 2>/dev/null || true
aws iam delete-instance-profile --instance-profile-name "$PROFILE_NAME" 2>/dev/null || true
aws iam detach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true

SG_ID=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
  --filters Name=group-name,Values="$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)
if [ -n "${SG_ID:-}" ] && [ "$SG_ID" != "None" ]; then
  say "Deleting security group $SG_ID"
  aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$SG_ID" 2>/dev/null || true
fi

say "Deleting key pair $KEY_NAME"
aws ec2 delete-key-pair --region "$AWS_REGION" --key-name "$KEY_NAME" 2>/dev/null || true
rm -f "${KEY_NAME}.pem"

say "Teardown complete. Verify in the console that nothing billable remains."
