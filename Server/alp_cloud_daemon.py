#!/usr/bin/env python3
"""
Alp Browser sync daemon.

Stores opaque, client-encrypted sidebar vaults, one file per vault id. The server never
sees plaintext: clients encrypt before upload, and this process only reads and writes bytes.

Endpoints (used by AlpSyncService):
    GET /health              -> {"status": "ok"}
    GET /v1/vault/<id>       -> the stored blob, or 404
    PUT /v1/vault/<id>       -> store the request body (max 15 MiB)

Configuration (environment):
    ALP_SYNC_PORT   listen port (default 8788)
    ALP_SYNC_DIR    storage root (default ~/.alp-cloud)
"""

import http.server
import json
import os
import re
from pathlib import Path

PORT = int(os.environ.get("ALP_SYNC_PORT", "8788"))
STORAGE_DIR = Path(os.environ.get("ALP_SYNC_DIR", str(Path.home() / ".alp-cloud")))
VAULTS_DIR = STORAGE_DIR / "vaults"
MAX_VAULT_BYTES = 15 * 1024 * 1024
VAULT_ID_RE = re.compile(r"^[a-z0-9_\-]{1,128}$")


def vault_path(vault_id: str) -> Path:
    return VAULTS_DIR / f"{vault_id}.enc"


class VaultHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # No request logging: nothing about who synced or when is kept.
        pass

    def _send_json(self, status: int, payload: dict):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _vault_id(self):
        """Returns the validated vault id from /v1/vault/<id>, or None."""
        parts = [p for p in self.path.split("?")[0].split("/") if p]
        if len(parts) != 3 or parts[0] != "v1" or parts[1] != "vault":
            return None
        vault_id = parts[2].lower()
        return vault_id if VAULT_ID_RE.match(vault_id) else None

    def do_GET(self):
        if self.path.split("?")[0] == "/health":
            self._send_json(200, {"status": "ok"})
            return

        vault_id = self._vault_id()
        if vault_id is None:
            self._send_json(404, {"error": "Not found"})
            return
        path = vault_path(vault_id)
        if not path.exists():
            self._send_json(404, {"error": "Vault not found"})
            return
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_PUT(self):
        vault_id = self._vault_id()
        if vault_id is None:
            self._send_json(404, {"error": "Not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_VAULT_BYTES:
            self._send_json(413, {"error": "Invalid payload size"})
            return
        body = self.rfile.read(length)
        VAULTS_DIR.mkdir(parents=True, exist_ok=True)
        target = vault_path(vault_id)
        tmp = target.with_suffix(".tmp")
        tmp.write_bytes(body)
        os.chmod(tmp, 0o600)
        tmp.replace(target)
        self._send_json(200, {"ok": True, "bytes_stored": len(body)})


def main():
    VAULTS_DIR.mkdir(parents=True, exist_ok=True)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), VaultHandler)
    print(f"Alp Browser sync daemon listening on 127.0.0.1:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
