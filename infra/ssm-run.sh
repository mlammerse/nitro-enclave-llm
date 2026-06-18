#!/usr/bin/env bash
# Run a shell script on the parent via SSM Run Command (non-interactive, as root).
# Usage:  ./ssm-run.sh < script.sh      OR      echo 'cmd' | ./ssm-run.sh
# Env:    TIMEOUT (default 3600s)
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env
IID="$(cat .instance-id)"
TIMEOUT="${TIMEOUT:-3600}"
SCRIPT="$(cat)"

PARAMS="$(SCRIPT="$SCRIPT" python3 -c 'import json,os;print(json.dumps({"commands":[os.environ["SCRIPT"]]}))')"
CID="$(aws ssm send-command --region "$AWS_REGION" --instance-ids "$IID" \
  --document-name AWS-RunShellScript --timeout-seconds "$TIMEOUT" \
  --parameters "$PARAMS" --query 'Command.CommandId' --output text)"
echo "CommandId=$CID  (instance $IID)" >&2

while true; do
  ST="$(aws ssm get-command-invocation --region "$AWS_REGION" --command-id "$CID" \
        --instance-id "$IID" --query 'Status' --output text 2>/dev/null || echo Pending)"
  case "$ST" in
    Success|Failed|Cancelled|TimedOut) break ;;
  esac
  sleep 5
done

aws ssm get-command-invocation --region "$AWS_REGION" --command-id "$CID" --instance-id "$IID" \
  --query '{Status:Status,Out:StandardOutputContent,Err:StandardErrorContent}' --output json \
  | python3 -c 'import json,sys;d=json.load(sys.stdin);print("STATUS:",d["Status"]);print("---STDOUT---");print(d["Out"]);print("---STDERR---");print(d["Err"])'
[ "$ST" = "Success" ]
