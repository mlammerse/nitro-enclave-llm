# Runbook — day-to-day operations

Step-by-step procedures. For *why*, see [architecture.md](architecture.md) and
[ops-manual.md](ops-manual.md).

Legend: 🖥️ = run on your **Mac**, ☁️ = run on the **EC2 parent** (inside an SSM shell).

---

## 0. One-time local setup 🖥️

```bash
aws --version                      # v2.x (installed via brew)
session-manager-plugin             # should print a version
aws configure                      # set Access Key, Secret, region=ap-southeast-2, output=json
aws sts get-caller-identity        # confirms credentials work
```

---

## 1. Provision AWS + launch the parent 🖥️

```bash
cd infra
./00-bootstrap-aws.sh              # creates key/IAM/SG, then prompts: type "launch"
```

Creates: EC2 key pair (`nitro-llm-key.pem`, break-glass only), IAM role +
instance profile (SSM), security group (no inbound), and a `c6i.2xlarge` with
enclaves enabled. The instance id is saved to `infra/.instance-id`.

---

## 2. Connect to the parent 🖥️ → ☁️

```bash
cd infra
./01-connect.sh                    # SSM shell (wait ~1-2 min after launch for SSM to register)
```

If it says the instance isn't connected yet, wait a minute and retry.

---

## 3. Install the enclave toolchain ☁️

```bash
# Get the repo onto the parent (clone your private repo, or scp). Then:
sudo bash parent/setup-parent.sh
exit                               # group membership (ne/docker) needs a fresh login
```
Reconnect with `./01-connect.sh`, then verify:
```bash
nitro-cli --version
docker ps                          # should not error (you're in the docker group)
```

---

## 4. Download the model ☁️

Llama 3.2 is **gated** — you must have accepted its license on HuggingFace and
have a read token.

```bash
export MODEL_REPO="bartowski/Llama-3.2-3B-Instruct-GGUF"
export MODEL_FILE="Llama-3.2-3B-Instruct-Q4_K_M.gguf"
export HF_TOKEN="hf_xxxxxxxx"      # read token; omit for the ungated Qwen2.5 fallback
bash parent/download-model.sh      # lands in enclave/model/
```

---

## 5. Build the enclave image ☁️

```bash
bash enclave/build-enclave.sh      # docker build -> EIF; prints PCR0/1/2
```
**Record PCR0** — it's the fingerprint you verify against later. ~5–10 min the
first time (downloads the python base image + builds the ~2.5 GB EIF).

---

## 6. Launch the enclave ☁️

```bash
bash enclave/run-enclave.sh        # production launch (PCRs real)
# Development with console output (PCRs ZEROED):
DEBUG=1 bash enclave/run-enclave.sh
nitro-cli describe-enclaves        # confirm State=RUNNING
```

---

## 7. Start the bridge + run your first inference ☁️

```bash
# In one shell on the parent:
python3 parent/vsock-bridge.py     # leave running (http 127.0.0.1:8080 -> vsock)

# In another SSM shell:
bash client/infer.sh "Explain AWS Nitro Enclaves in one sentence."
```
Expected: a JSON `{"completion": "..."}` with a coherent answer — **the model
responded from inside the enclave.**

Optional — reach it from your Mac 🖥️:
```bash
./infra/02-portforward.sh          # localhost:8080 -> parent:8080 over SSM
# then in another Mac terminal:
HOST=127.0.0.1 bash client/infer.sh "Hello from my laptop"
```

---

## 8. Stop / start to save money

```bash
# Stop (keeps disk + config, stops compute billing) 🖥️
aws ec2 stop-instances  --region ap-southeast-2 --instance-ids "$(cat infra/.instance-id)"
# Start again later 🖥️
aws ec2 start-instances --region ap-southeast-2 --instance-ids "$(cat infra/.instance-id)"
```
After a start, re-run steps 6–7 (enclaves don't survive a stop/reboot).

---

## 9. Full teardown 🖥️

```bash
./infra/teardown.sh                # terminates instance, deletes IAM/SG/key
```

---

## Common errors

| Symptom | Fix |
|---------|-----|
| `01-connect.sh`: TargetNotConnected | Wait for SSM agent (1–2 min after launch); confirm instance has the SSM instance profile. |
| `nitro-cli run-enclave` insufficient resources | Allocator reserves too little — raise `memory_mib`/`cpu_count` in `/etc/nitro_enclaves/allocator.yaml`, `sudo systemctl restart nitro-enclaves-allocator`. |
| `docker: permission denied` | You're not in the `docker` group yet — log out/in (re-run `01-connect.sh`). |
| `build-enclave`: cannot find model | Run `parent/download-model.sh`; confirm a `*.gguf` exists in `enclave/model/`. |
| HF `401 Gated` | Accept the model license on HF and export a valid `HF_TOKEN`, or switch to the Qwen2.5 fallback in `config.env`. |
| `infer.sh` 502 from bridge | Enclave not running (`nitro-cli describe-enclaves`) or wrong `ENCLAVE_CID`. |
| Out-of-memory loading model | Use a smaller quant (Q4_K_M → Q3) or a bigger instance; raise enclave memory. |
| **build-enclave E51** "artifacts path…/HOME not set" | Non-login shells (SSM Run Command) have no `HOME`. `export HOME=/root NITRO_CLI_ARTIFACTS=…` (build-enclave.sh does this). |
| **build-enclave E48** linuxkit "Create outputs:" empty | OOM building the ramfs — the model + 8 GB enclave reservation starve RAM. Add swap (`setup-parent.sh` does) and set `TMPDIR` to the EBS volume. |
| **run-enclave E26** "Insufficient memory… minimum should be N MB" | `--memory` (and `allocator.yaml`) must be ≥ ~1.3× the EIF size. Raise `ENCLAVE_MEM_MIB`. |
| **Allocator restart fails** raising memory at runtime | Hugepage fragmentation. Set the value in `allocator.yaml`, then **reboot** so it reserves at boot. |
| **Enclave exits instantly** / `console` E44 | App (PID 1) died. Capture boot log with `nitro-cli run-enclave … --debug-mode --attach-console`. Two classic causes below. |
| `execvpe: python: No such file or directory` (in enclave console) | Nitro init ignores image `PATH`. Use an **absolute** interpreter path in `CMD` (`/usr/local/bin/python`). |
| `libgomp.so.1: cannot open shared object file` | The compiled `libllama.so` needs OpenMP at runtime. Keep `libgomp1` installed (don't `autoremove` it). |
