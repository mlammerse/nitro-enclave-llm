#!/usr/bin/env bash
# Optional: forward the parent's inference port (8080) to your Mac via SSM,
# so you can curl the model from your laptop. Leave running in its own terminal.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env
INSTANCE_ID="${1:-$(cat .instance-id 2>/dev/null || true)}"
LOCAL_PORT="${2:-8080}"
[ -z "$INSTANCE_ID" ] && { echo "No instance id."; exit 1; }
echo "Forwarding localhost:${LOCAL_PORT} -> ${INSTANCE_ID}:${LISTEN_PORT}"
exec aws ssm start-session --region "$AWS_REGION" --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters "{\"portNumber\":[\"${LISTEN_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}"
