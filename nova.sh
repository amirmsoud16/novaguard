#!/bin/bash

# تنظیم مسیر پروژه به صورت ثابت
PROJECT_DIR="/root/novaguard"
if [ ! -f "$PROJECT_DIR/server.py" ]; then
    echo "[!] server.py در مسیر $PROJECT_DIR پیدا نشد! لطفاً پروژه را در این مسیر قرار دهید."
    exit 1
fi
cd "$PROJECT_DIR"

CONFIG_DIR="configs"
SERVER_SCRIPT="server.py"
CONFIG_FILE="config.json"

function restart_server() {
    pkill -f $SERVER_SCRIPT 2>/dev/null
    echo "[*] Restarting NovaGuard server..."
    nohup python3 $SERVER_SCRIPT > server.log 2>&1 &
    sleep 1
    echo "[*] Server restarted."
}

function change_port() {
    read -p "پورت جدید را وارد کنید: " newport
    if [[ ! $newport =~ ^[0-9]+$ ]]; then
        echo "پورت نامعتبر!"
        return
    fi
    if [ -f $CONFIG_FILE ]; then
        jq ".port = $newport" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
        echo "پورت به $newport تغییر یافت."
        restart_server
    else
        echo "فایل config.json پیدا نشد!"
    fi
}

while true; do
    echo "------ منوی مدیریت NovaGuard ------"
    echo "1) ساخت کانفیگ جدید"
    echo "2) حذف یک کانفیگ"
    echo "3) نمایش همه کانفیگ‌ها"
    echo "4) ری‌استارت سرور"
    echo "5) تغییر پورت سرور"
    echo "6) خروج"
    echo "7) نمایش کد کانفیک فعلی"
    read -p "شماره گزینه را وارد کنید: " choice

    case $choice in
        1)
            echo "در حال ساخت کانفیگ جدید..."
            python3 $SERVER_SCRIPT --generate-config
            ;;
        2)
            echo "در حال حذف کانفیگ..."
            read -p "نام کانفیگ را وارد کنید: " confname
            rm -f $CONFIG_DIR/$confname.json && echo "کانفیگ حذف شد." || echo "کانفیگ پیدا نشد."
            ;;
        3)
            echo "لیست کانفیگ‌ها:"
            ls $CONFIG_DIR/
            ;;
        4)
            restart_server
            ;;
        5)
            change_port
            ;;
        6)
            echo "خروج"
            break
            ;;
        7)
            echo "کد کانفیک فعلی:"
            python3 -c 'import server; print(server.generate_connection_code())'
            ;;
        *)
            echo "گزینه نامعتبر!"
            ;;
    esac
done 
