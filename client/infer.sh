#!/usr/bin/env bash
# Send a prompt to the enclave through the parent bridge.
# Usage: ./infer.sh "your prompt here" [max_tokens]
# Run on the parent, or on your Mac if 02-portforward.sh is active.
set -euo pipefail
PROMPT="${1:-Hello, who are you? Answer in one sentence.}"
MAX_TOKENS="${2:-128}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"

curl -s "http://${HOST}:${PORT}" \
  -H 'Content-Type: application/json' \
  -d "$(python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "max_tokens": int(sys.argv[2])}))' "$PROMPT" "$MAX_TOKENS")" \
  | python3 -m json.tool
