#!/bin/bash

set -e

function loading() {
    local pid=$1
    local msg=$2
    local spin='|/-\\'
    local i=0
    tput civis
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r$msg ${spin:$i:1}"
        sleep 0.1
    done
    tput cnorm
    printf "\r$msg ✓\n"
}

echo "---- NovaGuard Server Quick Installer ----"

# نصب پیش‌نیازها
(
    pip3 install --upgrade pip
    pip3 install -r requirements.txt
) &
loading $! "[1/3] Downloading & Installing Python requirements..."

# تولید گواهی SSL اگر وجود ندارد
if [ ! -f novaguard.crt ] || [ ! -f novaguard.key ]; then
    (
        bash generate_cert.sh
    ) &
    loading $! "[2/3] Generating self-signed SSL certificate..."
else
    echo "[2/3] SSL certificate already exists."
fi

echo "[3/3] Done!"
echo "To run the server, use:"
echo "python3 server.py" 