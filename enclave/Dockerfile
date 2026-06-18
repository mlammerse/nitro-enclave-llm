# Enclave image. Built into an EIF by `nitro-cli build-enclave`.
# The model is baked in so it's measured into PCR0 (attestable).
FROM python:3.11-slim

# CPU-only llama-cpp-python wheel (no compiler needed in the image).
RUN pip install --no-cache-dir \
      llama-cpp-python==0.3.4 \
      --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cpu

WORKDIR /app
# Model file is copied from the build context (parent/download-model.sh puts it here).
COPY model/*.gguf /model/model.gguf
COPY vsock-server.py /app/vsock-server.py

ENV MODEL_PATH=/model/model.gguf \
    VSOCK_PORT=5000 \
    N_CTX=2048

CMD ["python", "/app/vsock-server.py"]
