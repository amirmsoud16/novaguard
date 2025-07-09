#!/usr/bin/env python3
import os
import sys
import json
import base64
from cryptography.hazmat.primitives import hashes
from cryptography.x509 import load_pem_x509_certificate

def get_cert_fingerprint(certfile):
    with open(certfile, 'rb') as f:
        cert = load_pem_x509_certificate(f.read())
    fp = cert.fingerprint(hashes.SHA256())
    return ':'.join([fp.hex()[i:i+2].upper() for i in range(0, len(fp.hex()), 2)])

def generate_connection_code():
    config_path = 'config.json'
    if not os.path.exists(config_path):
        print("Error: config.json not found!", file=sys.stderr)
        return None
    
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    info = {
        "server": config["host"],
        "tcp_port": config["tcp_port"],
        "udp_port": config["udp_port"],
        "config_id": config.get("config_id", ""),
        "fingerprint": get_cert_fingerprint(config['certfile']),
        "protocol": config.get("protocol", "novaguard")
    }
    b64 = base64.urlsafe_b64encode(json.dumps(info).encode()).decode()
    return f"ng://{b64}"

if __name__ == "__main__":
    code = generate_connection_code()
    if code:
        print(code)
    else:
        sys.exit(1) 