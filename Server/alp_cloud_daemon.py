#!/usr/bin/env python3
"""
Alp Browser Cloud Sync Daemon
-----------------------------
Zero-knowledge client-encrypted browser state sync daemon for Alp Browser.
Stores per-user AES-256 client-encrypted vaults in ~/.arc2-cloud/vaults/<vault_id>.enc
"""

import os
import sys
from pathlib import Path

# Re-export and run the underlying daemon handler
sys.path.insert(0, str(Path(__file__).parent))
from oci_arc_cloud_daemon import *

if __name__ == "__main__":
    VAULTS_DIR.mkdir(parents=True, exist_ok=True)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), ArcPrivacyCloudHandler)
    print(f"Alp Browser Cloud Sync Daemon listening on 127.0.0.1:{PORT}")
    server.serve_forever()
