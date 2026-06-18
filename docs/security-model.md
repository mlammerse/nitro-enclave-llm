# Security Model

## Goal

Run inference such that the **code and model are tamper-evident and isolated**, and
prompts/responses are processed in an environment whose integrity can be
cryptographically attested.

## Trust boundaries

```
Untrusted ── Internet ──┐
                        │ (no inbound; egress only for setup)
Parent EC2 ─────────────┤  semi-trusted: brokers vsock, holds the EIF, can see
                        │  bridge traffic (plaintext in this PoC)
Enclave ────────────────┘  trusted compute: isolated, attestable, no network/disk
```

- **AWS operators / hypervisor**: Nitro's design excludes operator access to enclave
  memory; the enclave is isolated even from the parent's root user.
- **Parent root user**: can start/stop the enclave and *sees plaintext on the bridge*
  in this PoC. It cannot read enclave memory. Phase 2 (KMS-gated keys, encrypted
  vsock payloads) reduces what the parent can observe.

## What attestation proves (and doesn't)

The Nitro Security Module emits a COSE-signed **attestation document** containing the
**PCR** measurements, signed by a cert chained to the **AWS Nitro Attestation PKI root**.

**Proves:** the enclave is running an image whose measurement equals a known PCR0 —
i.e. exactly this code + this model, unmodified, on genuine Nitro hardware.

**Does not prove:** that the *application logic* is correct or benign — only that it
matches what you measured. You must trust (and review) the source that produced the EIF.

**Debug mode caveat:** `--debug-mode` zeros all PCRs and enables console access. An
attestation from a debug enclave is worthless for trust. Production launches omit it.

## Verification flow (PoC)

1. Build EIF from reviewed source → record PCR0 (`build-enclave.sh` output).
2. Launch **without** debug mode.
3. Confirm the running enclave's measurement matches the recorded PCR0.
4. (Phase 2) A remote verifier requests the attestation doc over vsock, validates the
   AWS root cert chain, and asserts PCR0 before sending secrets.

## Network & access controls

- Security group: **0 inbound rules**. No SSH exposed.
- Administrative access: **SSM Session Manager** — IAM-authenticated, CloudTrail-logged,
  no long-lived open port. Break-glass SSH key exists but is unused by default.
- Enclave: **no network interface at all** — exfiltration over the network is not
  possible from inside.

## Data handling

- Prompts/responses transit the parent bridge in plaintext **in this PoC**. For
  sensitive data, adopt Phase 2: encrypt payloads end-to-end with a key released by
  KMS only to the attested enclave.
- No persistent storage in the enclave → nothing retained after termination.
- Model weights: confidential at rest only once Phase 2's encrypted delivery is in
  place; in the PoC they sit on the parent EBS volume and inside the EIF.

## Secrets hygiene

- `.gitignore` blocks `*.pem`, `.env`, `*.gguf`, `*.eif`, `hf_token.txt`.
- AWS credentials live only in `~/.aws/` on your Mac; HF token passed via env var,
  never written to the repo.
- No secrets are baked into the EIF (only the open-weights model + code).

## Residual risks (PoC)

| Risk | Mitigation status |
|------|-------------------|
| Parent observes plaintext I/O | Accepted in PoC → Phase 2 encrypted vsock |
| No remote attestation check before use | Manual PCR0 compare → Phase 2 verifier |
| Model not confidential at rest | Accepted (open weights) |
| Broad admin IAM | Tighten to least-privilege in Phase 2 |
| Egress open during setup | Lock down / private subnet + VPC endpoints in Phase 2 |
