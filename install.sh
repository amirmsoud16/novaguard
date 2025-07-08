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

# 5. کلون پروژه در novaguard اگر وجود ندارد
if [ ! -d novaguard ]; then
    echo "[!] Cloning project into 'novaguard'..."
    git clone https://github.com/amirmsoud16/novaguard.git novaguard
else
    echo "[i] Directory 'novaguard' already exists. Skipping clone."
fi
cd novaguard

# 6. نصب پکیج‌های پایتون فقط اگر نیاز باشد
if [ -f requirements.txt ]; then
    REQUIREMENTS_INSTALLED=$(python3 -m pip freeze | grep -f requirements.txt | wc -l)
    if [ "$REQUIREMENTS_INSTALLED" -ne "$(cat requirements.txt | wc -l)" ]; then
        echo "[!] Installing/Upgrading Python requirements..."
        pip3 install --upgrade pip --break-system-packages
        pip3 install --break-system-packages -r requirements.txt
    else
        echo "[i] Python requirements already satisfied."
    fi
fi

# 7. تولید گواهی SSL اگر وجود ندارد
if [ ! -f novaguard.crt ] || [ ! -f novaguard.key ]; then
    bash generate_cert.sh
else
    echo "[i] SSL certificate already exists."
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
