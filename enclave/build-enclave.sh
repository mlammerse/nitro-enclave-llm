#!/usr/bin/env bash
# Run ON the EC2 parent. Builds the Docker image, converts it to an EIF, and
# records the PCR measurements (PCR0 = hash of the whole image, incl. the model).
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="nitro-llm:latest"
EIF="llm.eif"

# Sanity: model must be present before building (it gets baked in).
shopt -s nullglob
gguf=(model/*.gguf)
[ ${#gguf[@]} -gt 0 ] || { echo "No model in enclave/model/. Run parent/download-model.sh first."; exit 1; }

echo "==> Building Docker image $IMAGE (model: ${gguf[0]})"
docker build -t "$IMAGE" .

echo "==> Building enclave image file -> $EIF"
nitro-cli build-enclave --docker-uri "$IMAGE" --output-file "$EIF" | tee build-output.json

echo
echo "==> Measurements (record PCR0 for attestation verification):"
python3 - <<'PY'
import json
with open("build-output.json") as f:
    # build-output.json may have log lines before the JSON; grab the JSON object.
    data = f.read()
start = data.find("{")
m = json.loads(data[start:])["Measurements"]
for k in ("PCR0", "PCR1", "PCR2"):
    print(f"{k} = {m.get(k)}")
PY
