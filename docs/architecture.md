# Architecture

## Components

1. **Control plane (your Mac).** AWS CLI, GitHub CLI, SSM Session Manager plugin.
   Holds no model and runs no inference. Used to provision AWS, open an SSM shell,
   and (optionally) port-forward the inference endpoint to your laptop.

2. **Parent EC2 instance** (`c6i.2xlarge`, Amazon Linux 2023, Nitro, enclave-enabled).
   - Has network access (downloads the model from HuggingFace, installs packages).
   - Runs `nitro-cli`, Docker, and the Nitro Enclaves *allocator* (reserves vCPUs +
     memory for the enclave).
   - Runs `vsock-bridge.py`: a local HTTP listener on `127.0.0.1:8080` that relays
     requests to the enclave over `vsock` and returns the reply.
   - Reachable **only** via SSM Session Manager — the security group has **zero
     inbound rules**, no SSH port open.

3. **The enclave.** A separate, isolated VM carved from the parent by the Nitro
   hypervisor. It has:
   - **No network interface**, **no persistent storage**, **no SSH/console** (except
     debug mode), **no GPU**.
   - One channel only: `AF_VSOCK` to the parent.
   - A Nitro Security Module (`/dev/nsm`) that produces signed **attestation
     documents** containing the **PCR** measurements of the running image.
   - Contents: `vsock-server.py` + `llama-cpp-python` + the GGUF model, all baked
     into the Enclave Image File (EIF).

## Request flow

```
client/infer.sh
   │  HTTP POST {prompt, max_tokens}
   ▼
parent: vsock-bridge.py  (127.0.0.1:8080)
   │  newline-terminated JSON over AF_VSOCK  (CID 16, port 5000)
   ▼
enclave: vsock-server.py
   │  llama.cpp create_chat_completion (CPU)
   ▼
   {completion}  ──── back up the same path ────▶ stdout
```

## Why CPU-only / small model

Nitro Enclaves do not expose GPUs or accelerators. Inference uses the parent's
vCPUs reserved by the allocator. A 3B model quantized to Q4 (~2 GB) gives
interactive-ish latency on 4 vCPUs; larger models work but get slower. KV-cache +
runtime fit comfortably in the 8192 MiB reserved for the enclave.

## Why bake the model into the EIF

Baking the model in means it is **measured into PCR0** (the hash of the whole
enclave image). The attestation document therefore proves not just *which code*
but *which model weights* are running. The trade-off: the EIF is large (~2.5 GB)
and changing the model means a rebuild. Phase 2 covers streaming an encrypted model
in over vsock instead, with KMS releasing the key only to an attested enclave.

## Measurements (PCRs)

| PCR | Measures |
|-----|----------|
| PCR0 | Entire EIF (kernel + ramdisk + application + model) |
| PCR1 | Linux kernel + bootstrap |
| PCR2 | Application (user) ramdisk |
| PCR8 | (If signed) the EIF signing certificate |

`build-enclave.sh` prints PCR0/1/2 at build time. In **debug mode** all PCRs are
zeroed — debug is for development only, never for an attestation you trust.
