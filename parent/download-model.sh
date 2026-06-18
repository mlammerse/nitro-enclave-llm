#!/usr/bin/env bash
# Run ON the EC2 parent. Downloads the GGUF model onto the parent's EBS volume
# so it can be baked into the enclave image. The parent HAS network; the enclave does NOT.
#
# For gated models (Llama 3.2): export HF_TOKEN=hf_xxx first (read token, license accepted).
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL_REPO="${MODEL_REPO:-bartowski/Llama-3.2-3B-Instruct-GGUF}"
MODEL_FILE="${MODEL_FILE:-Llama-3.2-3B-Instruct-Q4_K_M.gguf}"
DEST="enclave/model"

echo "==> Installing huggingface_hub CLI..."
pip3 install -q -U "huggingface_hub[cli]"

if [ -n "${HF_TOKEN:-}" ]; then
  export HF_TOKEN
  echo "==> Using HF_TOKEN for gated download."
fi

echo "==> Downloading $MODEL_FILE from $MODEL_REPO -> $DEST"
mkdir -p "$DEST"
hf download "$MODEL_REPO" "$MODEL_FILE" --local-dir "$DEST"

echo "==> Model present:"
ls -lh "$DEST/$MODEL_FILE"
