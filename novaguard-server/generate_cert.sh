#!/bin/bash

# Generate self-signed certificate for NovaGuard server
openssl req -x509 -newkey rsa:4096 -keyout novaguard.key -out novaguard.crt -days 365 -nodes -subj "/C=IR/ST=Tehran/L=Tehran/O=NovaGuard/OU=IT/CN=novaguard.local"

echo "Certificate generated successfully!"
echo "Files created:"
echo "  - novaguard.crt (certificate)"
echo "  - novaguard.key (private key)" 