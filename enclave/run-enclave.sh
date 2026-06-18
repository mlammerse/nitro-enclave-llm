#!/usr/bin/env bash
# Run ON the EC2 parent. Launches (or relaunches) the enclave.
#   DEBUG=1 ./run-enclave.sh   -> debug mode + console (PCRs are ZEROED in debug mode)
set -euo pipefail
cd "$(dirname "$0")"

ENCLAVE_CID="${ENCLAVE_CID:-16}"
ENCLAVE_CPUS="${ENCLAVE_CPUS:-4}"
ENCLAVE_MEM_MIB="${ENCLAVE_MEM_MIB:-8192}"
EIF="llm.eif"

[ -f "$EIF" ] || { echo "$EIF not found. Run build-enclave.sh first."; exit 1; }

echo "==> Terminating any running enclaves..."
nitro-cli terminate-enclave --all >/dev/null 2>&1 || true

DEBUG_FLAG=""
if [ "${DEBUG:-0}" = "1" ]; then
  DEBUG_FLAG="--debug-mode"
  echo "==> DEBUG MODE (PCRs zeroed; attestation NOT valid for production)."
fi

echo "==> Running enclave: cid=$ENCLAVE_CID cpus=$ENCLAVE_CPUS mem=${ENCLAVE_MEM_MIB}MiB"
# shellcheck disable=SC2086
nitro-cli run-enclave \
  --eif-path "$EIF" \
  --cpu-count "$ENCLAVE_CPUS" \
  --memory "$ENCLAVE_MEM_MIB" \
  --enclave-cid "$ENCLAVE_CID" \
  $DEBUG_FLAG

echo "==> Running enclaves:"
nitro-cli describe-enclaves

if [ "${DEBUG:-0}" = "1" ]; then
  echo "==> Attaching to console (Ctrl-C to detach)..."
  EID=$(nitro-cli describe-enclaves | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["EnclaveID"])')
  nitro-cli console --enclave-id "$EID" || true
fi
