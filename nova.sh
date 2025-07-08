#!/bin/bash

# مسیر پروژه ثابت
PROJECT_DIR="/root/novaguard"
if [ ! -f "$PROJECT_DIR/server.py" ]; then
    echo "[!] server.py در مسیر $PROJECT_DIR پیدا نشد! لطفاً پروژه را در این مسیر قرار دهید."
    exit 1
fi
cd "$PROJECT_DIR"

CONFIG_DIR="configs"
SERVER_SCRIPT="server.py"
CONFIG_FILE="config.json"
HISTORY_FILE="$CONFIG_DIR/history.txt"

function is_server_running() {
    pgrep -f $SERVER_SCRIPT > /dev/null
}

function start_server_bg() {
    if is_server_running; then
        echo "[i] سرور در حال اجراست."
    else
        echo "[*] اجرای سرور در پس‌زمینه..."
        nohup python3 $SERVER_SCRIPT > server.log 2>&1 &
        sleep 1
        echo "[i] سرور اجرا شد."
    fi
}

function stop_server() {
    if is_server_running; then
        pkill -f $SERVER_SCRIPT
        echo "[🛑] سرور VPN خاموش شد."
    else
        echo "[i] سرور در حال اجرا نبود."
    fi
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

function show_menu() {
    echo -e "\n🌐 ------ \e[1mمنوی مدیریت NovaGuard\e[0m ------ 🌐"
    echo "1️⃣  ساخت کانفیک جدید"
    echo "2️⃣  حذف یک کانفیک 🗑️"
    echo "3️⃣  نمایش همه کانفیک‌ها 📜"
    echo "4️⃣  ری‌استارت سرور ♻️"
    echo "5️⃣  تغییر پورت سرور 🔧"
    echo "6️⃣  خروج 🚪"
    echo "7️⃣  نمایش کد کانفیک فعلی 📝"
    echo "8️⃣  🛑 خاموش کردن سرور VPN"
}

while true; do
    show_menu
    read -p "شماره گزینه را وارد کنید: " choice

    case $choice in
        1)
            start_server_bg
            echo "در حال ساخت کانفیک جدید..."
            CONFIG_CODE=$(python3 -c 'import server; print(server.generate_connection_code())')
            echo -e "\nکد کانفیک جدید:\n$CONFIG_CODE\n"
            mkdir -p $CONFIG_DIR
            echo "$CONFIG_CODE" >> $HISTORY_FILE
            read -p "مایلید به منو برگردید؟ (y/n): " back
            if [[ "$back" != "y" && "$back" != "Y" ]]; then
                echo "خروج از منو."
                exit 0
            fi
            ;;
        2)
            echo "در حال حذف کانفیگ..."
            read -p "شماره خط یا متن کانفیگ را وارد کنید: " confline
            if [[ -f $HISTORY_FILE ]]; then
                grep -v "$confline" $HISTORY_FILE > $HISTORY_FILE.tmp && mv $HISTORY_FILE.tmp $HISTORY_FILE
                echo "کانفیگ حذف شد (در صورت وجود)."
            else
                echo "هیچ کانفیگی ذخیره نشده است."
            fi
            ;;
        3)
            echo "📜 لیست کانفیک‌های ذخیره‌شده:"
            if [[ -f $HISTORY_FILE ]]; then
                nl -w2 -s'. ' $HISTORY_FILE
            else
                echo "هیچ کانفیگی ذخیره نشده است."
            fi
            ;;
        4)
            echo "♻️ ری‌استارت سرور..."
            stop_server
            start_server_bg
            ;;
        5)
            change_port
            ;;
        6)
            echo "🚪 خروج"
            break
            ;;
        7)
            echo "📝 کد کانفیک فعلی:"
            CONFIG_CODE=$(python3 -c 'import server; print(server.generate_connection_code())')
            echo "$CONFIG_CODE"
            ;;
        8)
            stop_server
            ;;
        *)
            echo "❗ گزینه نامعتبر!"
            ;;
    esac
done 
