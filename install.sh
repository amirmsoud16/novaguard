 #!/bin/bash

set -e

# نصب python3 و pip3 اگر وجود ندارند
if ! command -v python3 >/dev/null 2>&1; then
    echo "[!] Python3 not found. Installing..."
    apt update && apt install python3 -y
fi
if ! command -v pip3 >/dev/null 2>&1; then
    echo "[!] pip3 not found. Installing..."
    apt update && apt install python3-pip -y
fi

# نصب git اگر وجود ندارد
if ! command -v git >/dev/null 2>&1; then
    echo "[!] git not found. Installing..."
    apt update && apt install git -y
fi

# نصب jq اگر وجود ندارد
if ! command -v jq >/dev/null 2>&1; then
    echo "[!] jq not found. Installing..."
    apt update && apt install jq -y
fi

# اگر فایل server.py وجود ندارد، پروژه را در فولدر novaguard کلون کن
if [ ! -f server.py ]; then
    echo "[!] Project files not found. Creating 'novaguard' directory and cloning from GitHub..."
    mkdir -p novaguard
    cd novaguard
    git clone https://github.com/amirmsoud16/novaguard.git .
fi

# نصب وابستگی‌های پایتون
pip3 install --upgrade pip
pip3 install -r requirements.txt

# تولید گواهی SSL اگر وجود ندارد
if [ ! -f novaguard.crt ] || [ ! -f novaguard.key ]; then
    bash generate_cert.sh
else
    echo "[2/3] SSL certificate already exists."
fi

# پیدا کردن مسیر واقعی nova.sh حتی اگر اسکریپت از هر مسیری اجرا شود
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

echo "[3/3] Done!"
echo "سرور نصب شد. برای مدیریت و دریافت کانفیک، دستور زیر را اجرا کنید:"
echo "sudo nova" 
