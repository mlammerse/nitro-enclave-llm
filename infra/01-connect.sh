#!/usr/bin/env bash
# Open an SSM Session Manager shell to the parent instance (no SSH, no open ports).
# Requires the Session Manager plugin:  brew install --cask session-manager-plugin
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env
INSTANCE_ID="${1:-$(cat .instance-id 2>/dev/null || true)}"
[ -z "$INSTANCE_ID" ] && { echo "No instance id. Pass one or run 00-bootstrap-aws.sh first."; exit 1; }
echo "Connecting to $INSTANCE_ID via SSM ..."
exec aws ssm start-session --region "$AWS_REGION" --target "$INSTANCE_ID"
