#!/usr/bin/env bash
# Run ON the EC2 parent. Builds the Docker image, converts it to an EIF, and
# records the PCR measurements (PCR0 = hash of the whole image, incl. the model).
set -eo pipefail
cd "$(dirname "$0")"

IMAGE="nitro-llm:latest"
EIF="llm.eif"

# nitro-cli needs HOME (for default artifact dir) and a writable artifacts/temp
# dir. The build also loads the whole image into RAM to make the ramfs, so point
# TMPDIR at the EBS volume and ensure swap exists (the model + 8GB enclave
# reservation otherwise OOM-kills linuxkit). See docs/runbook.md.
export HOME="${HOME:-/root}"
export NITRO_CLI_ARTIFACTS="${NITRO_CLI_ARTIFACTS:-$(pwd)/../artifacts}"
export TMPDIR="${TMPDIR:-$(pwd)/../tmp}"
mkdir -p "$NITRO_CLI_ARTIFACTS" "$TMPDIR"

if ! swapon --show 2>/dev/null | grep -q .; then
  echo "WARNING: no swap active. EIF build of a multi-GB model may OOM."
  echo "  sudo fallocate -l 8G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
fi

shopt -s nullglob
gguf=(model/*.gguf)
[ ${#gguf[@]} -gt 0 ] || { echo "No model in enclave/model/. Run parent/download-model.sh first."; exit 1; }

echo "==> Building Docker image $IMAGE (model: ${gguf[0]})"
docker build -t "$IMAGE" .

echo "==> Building enclave image file -> $EIF"
nitro-cli build-enclave --docker-uri "$IMAGE" --output-file "$EIF" > build-output.json 2>&1 || { cat build-output.json; exit 1; }

echo
echo "==> Measurements (record PCR0 for attestation verification):"
python3 - <<'PY'
import json
data = open("build-output.json").read()
m = json.loads(data[data.find("{"):])["Measurements"]
for k in ("PCR0", "PCR1", "PCR2"):
    print(f"{k} = {m.get(k)}")
PY
ls -lh "$EIF"
