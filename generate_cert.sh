#!/bin/bash

CERT_NAME=novaguard
openssl req -x509 -newkey rsa:4096 -keyout $CERT_NAME.key -out $CERT_NAME.crt -days 3650 -nodes -subj "/CN=novaguard"
echo "Self-signed certificate and key generated: $CERT_NAME.crt, $CERT_NAME.key"
