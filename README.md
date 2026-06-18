# nitro-enclave-llm

Confidential LLM inference on **AWS Nitro Enclaves**. An open-weights GGUF model
(default: Llama 3.2 3B Instruct, Q4) runs inside a hardware-isolated, attestable
enclave with **no network, no persistent storage, and no interactive access** —
the only I/O is a `vsock` channel to the parent EC2 instance, which proxies
requests in and responses out.

> Why: process sensitive prompts in an environment whose exact code + model you
> can cryptographically prove (via the Nitro attestation document / PCR0) has not
> been tampered with. Useful for data-sovereignty / confidential-computing work.

## Architecture (PoC)

```
  Your Mac (control plane)                AWS ap-southeast-2 (Sydney)
  ┌──────────────────────┐                ┌───────────────────────────────────────┐
  │ aws cli / gh / ssm    │   SSM session  │  EC2 parent  (c6i.2xlarge, AL2023)      │
  │ docs + scripts        │───────────────▶│                                         │
  └──────────────────────┘                │   vsock-bridge.py  (127.0.0.1:8080)     │
                                           │            │  AF_VSOCK CID 16:5000       │
                                           │            ▼                            │
                                           │   ┌─────────────────────────────────┐  │
                                           │   │  Nitro Enclave (no net/disk)     │  │
                                           │   │  vsock-server.py + llama.cpp     │  │
                                           │   │  Llama 3.2 3B Q4 (baked in)      │  │
                                           │   └─────────────────────────────────┘  │
                                           └───────────────────────────────────────┘
```

Key constraint: **enclaves have no GPU** → CPU-only inference → small quantized model.

## Repo layout

| Path | What |
|------|------|
| `infra/`   | AWS provisioning: bootstrap, connect, port-forward, teardown |
| `parent/`  | Runs on the EC2 parent: toolchain setup, model download, vsock bridge |
| `enclave/` | Dockerfile + vsock inference server + build/run scripts |
| `client/`  | `infer.sh` — send a prompt, get a completion |
| `docs/`    | `runbook.md`, `ops-manual.md`, `architecture.md`, `security-model.md` |

## Quick start

See **[docs/runbook.md](docs/runbook.md)** for the full step-by-step. In short:

```bash
# 1. Local (Mac)
aws configure                       # region ap-southeast-2
./infra/00-bootstrap-aws.sh         # creates IAM/SG/key, launches parent (prompts for spend)
./infra/01-connect.sh               # SSM shell into the parent

# 2. On the parent
sudo bash parent/setup-parent.sh    # nitro-cli + docker + allocator   (then reconnect)
HF_TOKEN=hf_xxx bash parent/download-model.sh
bash enclave/build-enclave.sh       # builds EIF, prints PCR0
bash enclave/run-enclave.sh         # launches the enclave
python3 parent/vsock-bridge.py &    # start the bridge

# 3. First response
bash client/infer.sh "Explain Nitro Enclaves in one sentence."
```

**Stop the instance when idle. Run `./infra/teardown.sh` to remove everything.**

## Cost

`c6i.2xlarge` ≈ US$0.42/hr on-demand in Sydney. Stopped instance bills only EBS
(~a few US$/mo for 30 GB gp3). Teardown removes all billable resources.
