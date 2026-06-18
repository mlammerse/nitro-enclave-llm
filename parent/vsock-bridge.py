#!/usr/bin/env python3
"""Parent-side bridge: HTTP on 127.0.0.1:LISTEN_PORT  <->  vsock(enclave CID:VSOCK_PORT).

The enclave has no network — only AF_VSOCK to the parent. This bridge lets you
`curl` the parent locally; it forwards the request body to the enclave as a
newline-terminated JSON message and returns the enclave's JSON reply.

Run on the parent (after the enclave is running):
    ENCLAVE_CID=16 VSOCK_PORT=5000 LISTEN_PORT=8080 python3 vsock-bridge.py
"""
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ENCLAVE_CID = int(os.environ.get("ENCLAVE_CID", "16"))
VSOCK_PORT = int(os.environ.get("VSOCK_PORT", "5000"))
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8080"))


def _recv_line(sock: socket.socket) -> bytes:
    buf = b""
    while b"\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            break
        buf += chunk
    return buf


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        try:
            vs = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
            vs.settimeout(300)
            vs.connect((ENCLAVE_CID, VSOCK_PORT))
            vs.sendall(body.rstrip() + b"\n")
            reply = _recv_line(vs)
            vs.close()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(reply if reply.endswith(b"\n") else reply + b"\n")
        except Exception as exc:  # noqa: BLE001
            payload = json.dumps({"error": str(exc)}).encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(payload)

    def log_message(self, *_):  # quiet
        pass


if __name__ == "__main__":
    print(f"bridge: http://127.0.0.1:{LISTEN_PORT} -> vsock CID {ENCLAVE_CID}:{VSOCK_PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", LISTEN_PORT), Handler).serve_forever()
