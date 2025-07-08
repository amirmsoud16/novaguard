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
if [ ! -f novaguard.crt ] || [ ! -f novaguard.key ]; then
    bash generate_cert.sh
else
    echo "[i] SSL certificate already exists."
fi

# --- ساخت یا بروزرسانی خودکار فایل کانفیک novaguard/config.json با IP سرور ---
CONFIG_PATH="novaguard/config.json"
# اطمینان از وجود دایرکتوری والد
mkdir -p $(dirname "$CONFIG_PATH")
# ابتدا فایل کانفیک را با host پیش‌فرض بساز
cat > "$CONFIG_PATH" <<EOF
{
  "host": "0.0.0.0",
  "port": 443,
  "certfile": "novaguard.crt",
  "keyfile": "novaguard.key",
  "protocol": "novaguard-v1"
}
EOF
# سپس مقدار host را با IP سرور جایگزین کن
SERVER_IP=$(curl -s ifconfig.me)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi
if [ -n "$SERVER_IP" ]; then
    sed -i "s/\"host\": \".*\"/\"host\": \"$SERVER_IP\"/" "$CONFIG_PATH"
    echo "[i] IP سرور به صورت خودکار در $CONFIG_PATH قرار گرفت: $SERVER_IP"
else
    echo "[!] نتوانستم IP سرور را به صورت خودکار تشخیص دهم. مقدار host را دستی وارد کنید."
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
