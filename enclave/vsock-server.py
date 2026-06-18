#!/usr/bin/env python3
"""Inference server that runs INSIDE the enclave.

No network. Listens on AF_VSOCK and answers newline-terminated JSON requests:
    {"prompt": "...", "max_tokens": 128}  ->  {"completion": "..."}

The GGUF model is baked into the enclave image (measured into PCR0), so the
attestation document proves exactly which model + code are running.
"""
import json
import os
import socket

from llama_cpp import Llama

VSOCK_PORT = int(os.environ.get("VSOCK_PORT", "5000"))
MODEL_PATH = os.environ.get("MODEL_PATH", "/model/model.gguf")
N_CTX = int(os.environ.get("N_CTX", "2048"))

print(f"loading model: {MODEL_PATH}", flush=True)
llm = Llama(model_path=MODEL_PATH, n_ctx=N_CTX, n_threads=os.cpu_count(), verbose=False)
print("model loaded", flush=True)


def _recv_line(conn: socket.socket) -> bytes:
    buf = b""
    while b"\n" not in buf:
        chunk = conn.recv(4096)
        if not chunk:
            break
        buf += chunk
    return buf


def handle(conn: socket.socket) -> None:
    try:
        raw = _recv_line(conn)
        if not raw.strip():
            return
        req = json.loads(raw.decode())
        prompt = req.get("prompt", "")
        max_tokens = int(req.get("max_tokens", 128))
        out = llm.create_chat_completion(
            messages=[{"role": "user", "content": prompt}],
            max_tokens=max_tokens,
        )
        text = out["choices"][0]["message"]["content"]
        conn.sendall(json.dumps({"completion": text}).encode() + b"\n")
    except Exception as exc:  # noqa: BLE001
        try:
            conn.sendall(json.dumps({"error": str(exc)}).encode() + b"\n")
        except OSError:
            pass
    finally:
        conn.close()


def main() -> None:
    srv = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    srv.bind((socket.VMADDR_CID_ANY, VSOCK_PORT))
    srv.listen(8)
    print(f"listening on vsock port {VSOCK_PORT}", flush=True)
    while True:
        conn, _ = srv.accept()
        handle(conn)


if __name__ == "__main__":
    main()
