# Enclave image. Built into an EIF by `nitro-cli build-enclave`.
# The model is baked in so it's measured into PCR0 (attestable).
FROM python:3.11-slim

# Build tools to compile llama-cpp-python from source, PLUS libgomp1 which the
# compiled libllama.so needs AT RUNTIME (do NOT let autoremove take it).
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git ca-certificates libgomp1 \
    && pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir llama-cpp-python==0.3.4 \
    && apt-get purge -y build-essential cmake git && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# Model file comes from the build context (parent/download-model.sh puts it in model/).
COPY model/*.gguf /model/model.gguf
COPY vsock-server.py /app/vsock-server.py

ENV MODEL_PATH=/model/model.gguf \
    VSOCK_PORT=5000 \
    N_CTX=2048

# IMPORTANT: use the ABSOLUTE interpreter path. The Nitro enclave init does not
# honour the image PATH, so a bare ["python", ...] fails with
# "execvpe: python: No such file or directory" and the enclave reboots instantly.
CMD ["/usr/local/bin/python", "/app/vsock-server.py"]
