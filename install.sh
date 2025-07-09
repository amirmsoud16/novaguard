 #!/bin/bash

set -e

# 1. نصب python3 اگر نصب نیست
if ! command -v python3 >/dev/null 2>&1; then
    echo "[!] Python3 not found. Installing..."
    apt update && apt install python3 -y
else
    echo "[i] Python3 already installed."
fi

# 2. نصب pip3 اگر نصب نیست
if ! command -v pip3 >/dev/null 2>&1; then
    echo "[!] pip3 not found. Installing..."
    apt update && apt install python3-pip -y
else
    echo "[i] pip3 already installed."
fi

# 3. نصب git اگر نصب نیست
if ! command -v git >/dev/null 2>&1; then
    echo "[!] git not found. Installing..."
    apt update && apt install git -y
else
    echo "[i] git already installed."
fi

# 4. نصب jq اگر نصب نیست
if ! command -v jq >/dev/null 2>&1; then
    echo "[!] jq not found. Installing..."
    apt update && apt install jq -y
else
    echo "[i] jq already installed."
fi

# 5. حذف پوشه novaguard اگر وجود دارد، سپس کلون پروژه
if [ -d novaguard ]; then
    echo "[!] Directory 'novaguard' already exists. Removing for clean install..."
    rm -rf novaguard
fi

echo "[!] Cloning project into 'novaguard'..."
git clone https://github.com/amirmsoud16/novaguard.git novaguard
cd novaguard

# 6. ساخت و استفاده از محیط مجازی پایتون (venv) برای نصب پکیج‌ها
if [ ! -d venv ]; then
    echo "[!] Creating Python virtual environment..."
    apt install python3-venv -y
    python3 -m venv venv
fi

# فعال‌سازی محیط مجازی و نصب پکیج‌ها
source venv/bin/activate
pip install -r requirements.txt
# غیرفعال‌سازی محیط مجازی
deactivate

# 7. تولید گواهی SSL اگر وجود ندارد
if [ ! -f /root/novaguard/novaguard.crt ] || [ ! -f /root/novaguard/novaguard.key ]; then
    bash generate_cert.sh
else
    echo "[i] SSL certificate already exists."
fi

# --- ساخت یا بروزرسانی خودکار فایل کانفیک novaguard/config.json با IP سرور ---
CONFIG_PATH="/root/novaguard/config.json"
mkdir -p $(dirname "$CONFIG_PATH")
> "$CONFIG_PATH"
# تشخیص IP سرور (ترجیحاً public)
SERVER_IP=$(curl -s ifconfig.me)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi
TCP_PORT=8443
UDP_PORT=1195
CONFIG_ID=$(cat /proc/sys/kernel/random/uuid)
SESSION_ID=$(cat /proc/sys/kernel/random/uuid)
cat > "$CONFIG_PATH" <<EOF
{
  "host": "$SERVER_IP",
  "tcp_port": 8443,
  "udp_port": 1195,
  "config_id": "$CONFIG_ID",
  "session_id": "$SESSION_ID",
  "certfile": "/root/novaguard/novaguard.crt",
  "keyfile": "/root/novaguard/novaguard.key",
  "protocol": "novaguard-v1",
  "version": "1.0.0"
}
EOF
echo "[i] فایل کانفیک با IP $SERVER_IP ساخته شد: $CONFIG_PATH"
# ایجاد endpoint برای دانلود سرتیفیکیت
if ! grep -q 'def serve_cert' server.py; then
cat <<'PYEND' >> server.py
from http.server import SimpleHTTPRequestHandler, HTTPServer
import threading

def serve_cert():
    class Handler(SimpleHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/novaguard.crt':
                self.send_response(200)
                self.send_header('Content-type', 'application/x-x509-ca-cert')
                self.end_headers()
                with open('/root/novaguard/novaguard.crt', 'rb') as f:
                    self.wfile.write(f.read())
            else:
                self.send_response(404)
                self.end_headers()
    t = threading.Thread(target=lambda: HTTPServer(("0.0.0.0", 8080), Handler).serve_forever(), daemon=True)
    t.start()
serve_cert()
PYEND
fi

# 8. نصب منوی nova
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOVA_PATH="$SCRIPT_DIR/nova.sh"
if [ ! -f $NOVA_PATH ]; then
    if [ -f ./nova.sh ]; then
        NOVA_PATH=./nova.sh
    elif [ -f ../nova.sh ]; then
        NOVA_PATH=../nova.sh
    else
        echo "[!] nova.sh پیدا نشد!"
        exit 1
    fi
fi
cp "$NOVA_PATH" /usr/local/bin/nova
chmod +x /usr/local/bin/nova

echo "[✔] نصب کامل شد. برای مدیریت و ساخت کانفیک، دستور زیر را اجرا کنید:"
echo "sudo nova" 
