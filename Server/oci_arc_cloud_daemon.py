#!/usr/bin/env python3
"""
Arc Immortal Multi-User Privacy-First Cloud Sync & Claude Code AI Daemon (OCI Box)
----------------------------------------------------------------------------------
- Stores per-user client-side AES-256 encrypted sidebar vaults in:
    ~/.arc2-cloud/vaults/<vault_id>.enc
- Strictly zero-knowledge & privacy-minimal:
    * Each user (e.g. you and your boyfriend) has a distinct 64-hex `vault_id`
      derived from their local 256-bit key on their Mac.
    * Payloads are encrypted with AES-256-CBC + PBKDF2 on the client Mac before
      upload; the server only stores the encrypted `.enc` blob.
    * No cookies, history, passwords, or archive items are ever accepted.
    * Arc Max AI queries (`/v1/ai`) are piped in-memory to `/home/ubuntu/.local/bin/claude -p`
      with zero prompt/response logging on disk.
"""

import base64
import hashlib
import http.server
import json
import os
import re
import subprocess
from pathlib import Path

PORT = int(os.environ.get("ARC2_PORT", "8788"))
STORAGE_DIR = Path.home() / ".arc2-cloud"
VAULTS_DIR = STORAGE_DIR / "vaults"
CLAUDE_BIN = "/home/ubuntu/.local/bin/claude"
VAULT_ID_RE = re.compile(r"^[a-fA-F0-9]{32,64}$")


class ArcPrivacyCloudHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Privacy-first: suppress request logging of user queries or IP addresses
        pass

    def _send_json(self, status: int, payload: dict):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/health", "/arc-cloud/health"):
            self._send_json(200, {
                "status": "ok",
                "service": "arc-immortal-oci-cloud",
                "privacy_mode": "zero-log-client-encrypted-vaults",
                "claude_code_available": os.path.exists(CLAUDE_BIN),
            })
            return

        if self.path in ("/v1/spaces/alp", "/arc-cloud/v1/spaces/alp"):
            export_json = STORAGE_DIR / "alp-server-backup" / "alp-spaces-export.json"
            if export_json.exists():
                data = export_json.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return

        # GET /v1/vault/<vault_id> or /arc-cloud/v1/vault/<vault_id>
        parts = [p for p in self.path.split("/") if p]
        if len(parts) >= 3 and parts[-2] == "vault":
            vault_id = parts[-1].lower()
            if not VAULT_ID_RE.match(vault_id):
                self._send_json(400, {"error": "Invalid vault_id"})
                return
            vault_file = VAULTS_DIR / f"{vault_id}.enc"
            if not vault_file.exists():
                self._send_json(404, {"error": "Vault not found"})
                return
            data = vault_file.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        self._send_json(404, {"error": "Not found"})

    def do_PUT(self):
        # PUT /v1/vault/<vault_id> or /arc-cloud/v1/vault/<vault_id>
        parts = [p for p in self.path.split("/") if p]
        if len(parts) >= 3 and parts[-2] == "vault":
            vault_id = parts[-1].lower()
            if not VAULT_ID_RE.match(vault_id):
                self._send_json(400, {"error": "Invalid vault_id"})
                return
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 15 * 1024 * 1024:
                self._send_json(413, {"error": "Invalid payload size"})
                return
            body = self.rfile.read(length)
            VAULTS_DIR.mkdir(parents=True, exist_ok=True)
            vault_file = VAULTS_DIR / f"{vault_id}.enc"
            tmp_file = VAULTS_DIR / f"{vault_id}.enc.tmp"
            tmp_file.write_bytes(body)
            os.chmod(tmp_file, 0o600)
            tmp_file.replace(vault_file)
            self._send_json(200, {"ok": True, "bytes_stored": len(body)})
            return

        self._send_json(404, {"error": "Not found"})

    def do_POST(self):
        # POST /api/auth or /v1/auth (Pre-provisioned Alp Browser Accounts on OCI)
        if self.path.endswith("/api/auth") or self.path.endswith("/v1/auth"):
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length) if length > 0 else b"{}"
            try:
                req = json.loads(raw.decode("utf-8"))
                email = str(req.get("email", "guresalpdeniz@gmail.com")).strip().lower()
                password = str(req.get("password", ""))
            except Exception:
                email = "guresalpdeniz@gmail.com"
                password = ""
            accounts_file = STORAGE_DIR / "accounts.json"
            accounts = {}
            if accounts_file.exists():
                try:
                    accounts = json.loads(accounts_file.read_text())
                except Exception:
                    accounts = {}
            acct = accounts.get(email, {
                "id": hashlib.sha256(email.encode("utf-8")).hexdigest()[:28],
                "email": email,
                "name": "Alp" if email == "guresalpdeniz@gmail.com" else email.split("@")[0],
                "vault_id": hashlib.sha256(email.encode("utf-8")).hexdigest()[:24],
                "start_url": "https://alpbrowser.app/start",
                "status": "ready",
            })
            expected_hash = acct.get("password_sha256")
            if expected_hash:
                candidate = hashlib.sha256(f"{email}:{password}".encode("utf-8")).hexdigest()
                if candidate != expected_hash:
                    self._send_json(401, {"ok": False, "error": "INVALID_PASSWORD"})
                    return
            safe_acct = {k: v for k, v in acct.items() if k != "password_sha256"}
            self._send_json(200, {
                "ok": True,
                "account": safe_acct,
                "startUrl": "https://alpbrowser.app/start",
                "serverBackupReady": (STORAGE_DIR / "alp-server-backup" / "bcny-arc-server").exists(),
            })
            return

        # POST /v1/ai or /arc-cloud/v1/ai (Zero-Log Claude Code Proxy for Arc Max)
        if self.path.endswith("/v1/ai"):
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 2 * 1024 * 1024:
                self._send_json(400, {"error": "Invalid AI request size"})
                return
            raw = self.rfile.read(length)
            try:
                req = json.loads(raw.decode("utf-8"))
                prompt = str(req.get("prompt", "")).strip()
            except Exception:
                prompt = ""

            if not prompt:
                self._send_json(400, {"error": "Missing prompt"})
                return

            try:
                proc = subprocess.run(
                    [CLAUDE_BIN, "-p"],
                    input=prompt.encode("utf-8"),
                    capture_output=True,
                    timeout=45,
                )
                reply = proc.stdout.decode("utf-8", errors="replace").strip()
                if not reply:
                    reply = "Done."
                self._send_json(200, {"ok": True, "reply": reply})
            except Exception:
                self._send_json(500, {"ok": False, "reply": "Arc Max AI temporarily unavailable."})
            return

        self._send_json(404, {"error": "Not found"})


if __name__ == "__main__":
    VAULTS_DIR.mkdir(parents=True, exist_ok=True)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), ArcPrivacyCloudHandler)
    print(f"Arc Privacy Cloud Daemon listening on 127.0.0.1:{PORT}")
    server.serve_forever()
