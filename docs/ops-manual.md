# Operations Manual

Reference for running, tuning, securing, and decommissioning the system. For the
exact command sequence, see [runbook.md](runbook.md).

## 1. System overview

A single EC2 parent hosts one Nitro Enclave running a GGUF model on CPU. The parent
brokers all traffic over `vsock`. Access to the parent is SSM-only; the enclave has
no network, disk, or interactive access. See [architecture.md](architecture.md).

## 2. Capacity & resource tuning

The allocator (`/etc/nitro_enclaves/allocator.yaml`) reserves vCPUs + memory away
from the parent for the enclave. `run-enclave.sh` must request **≤** what's reserved.

| Lever | Where | Notes |
|-------|-------|-------|
| `memory_mib` | `allocator.yaml` | Must hold model + KV cache + runtime. 8192 MiB fits a 3B Q4. |
| `cpu_count`  | `allocator.yaml` | Whole cores; leave ≥2 for the parent. More cores ≈ faster tokens. |
| `--memory` / `--cpu-count` | `run-enclave.sh` | Per-launch request; ≤ allocator reservation. |
| `N_CTX` | enclave env | Context window; larger = more KV memory. |
| Quant level | `MODEL_FILE` | Q4_K_M balances size/quality; drop to Q3 if memory-bound. |
| Instance size | `config.env` | `c6i.2xlarge` (8/16). Bigger model → `c6i.4xlarge`+. |

After editing `allocator.yaml`: `sudo systemctl restart nitro-enclaves-allocator`.

## 3. Model management

- **Swap models** by changing `MODEL_REPO`/`MODEL_FILE` in `config.env` (or env
  vars), re-running `download-model.sh`, then `build-enclave.sh` (new PCR0) and
  `run-enclave.sh`. Any GGUF works within memory limits.
- **Gated models** (Llama) need license acceptance + `HF_TOKEN`. Ungated default:
  `Qwen/Qwen2.5-3B-Instruct-GGUF`.
- The model is **baked into the EIF** → changing it changes PCR0 (by design — the
  attestation pins the exact weights).

## 4. Monitoring & logs

- Enclave state: `nitro-cli describe-enclaves`.
- Enclave stdout (dev only): `DEBUG=1 ./run-enclave.sh` attaches the console.
- Bridge/inference logs: stdout of `vsock-bridge.py`.
- Parent host metrics: standard EC2 CloudWatch (CPU, disk). Enclave internals are
  intentionally opaque — that's the isolation guarantee. Phase 2 adds structured
  log export over vsock if you need it.

## 5. Cost management

| Item | ~Cost (Sydney, on-demand) |
|------|---------------------------|
| `c6i.2xlarge` running | ≈ US$0.42 / hr |
| `c6i.2xlarge` **stopped** | $0 compute; EBS only |
| 30 GB gp3 EBS | ≈ US$2.40 / mo |
| Data transfer (model pull) | one-off, small |

Practice: **stop the instance between sessions** (runbook §8). Run `teardown.sh`
when done. Set a small AWS Budgets alert as a backstop.

## 6. Teardown

`infra/teardown.sh` terminates the instance and deletes the IAM role/profile,
security group, and key pair. Afterwards confirm in the console that no instance,
volume, or Elastic IP lingers. The local `.pem` is removed too.

## 7. Security model (summary)

Full detail in [security-model.md](security-model.md). Headlines:

- **No inbound network** to the parent; access is SSM (IAM-authenticated, logged).
- **Enclave isolation**: no network/disk/interactive access; only vsock.
- **Attestation**: PCR0 pins code + model. Verify the running enclave's PCR0 against
  the value recorded at build time (and, in Phase 2, gate KMS key release on it).
- **Debug mode zeros PCRs** — never trust attestation from a debug-mode enclave.
- **Secrets** (HF token, AWS keys) never committed; `.gitignore` blocks `*.pem`,
  `.env`, `*.gguf`, `*.eif`.

## 8. Incident / recovery

| Situation | Action |
|-----------|--------|
| Enclave crashed/OOM | `nitro-cli terminate-enclave --all`; lower mem footprint; relaunch. |
| Parent unresponsive | Reboot via console/CLI; re-run runbook §6–7 (enclave is ephemeral). |
| Lost SSM access | Check instance profile still attached + SSM agent running; break-glass SSH via key pair as last resort (requires temporarily opening 22 — re-close after). |
| Suspected tamper | Rebuild EIF from source, compare PCR0 to the trusted recorded value. |

## 9. Phase-2 hardening roadmap

1. **KMS attestation-gated key release** — store secrets/model key in KMS with a key
   policy condition (`kms:RecipientAttestation:PCR0`) so only the attested enclave
   can decrypt. Use `kmstool-enclave-cli` + the `vsock-proxy` that ships with nitro-cli.
2. **Encrypted model delivery over vsock** instead of baking in — smaller EIF,
   model confidential at rest, weights released only post-attestation.
3. **Attestation verification client** — parse the COSE-signed attestation doc,
   validate the AWS Nitro root cert chain, assert expected PCR0.
4. **Least-privilege IAM** + **private subnet** with VPC endpoints (SSM, KMS, S3),
   no IGW.
5. **CloudWatch logs/metrics**, AWS Budgets alarms.
6. **Infrastructure as Code** — port `00-bootstrap-aws.sh` to Terraform or CDK.
7. **Signed EIFs** (PCR8) and a release/signing process.
