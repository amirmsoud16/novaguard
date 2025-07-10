#!/bin/bash

PROJECT_DIR="$(dirname "$0")"
cd "$PROJECT_DIR"
SERVER_NAME="novaguard-server"
PID_FILE="novaguard-server.pid"
LOG_FILE="novaguard-server.log"
CONFIG_FILE="config.json"
HISTORY_FILE="configs/history.txt"

function is_server_running() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

function start_server_bg() {
    if is_server_running; then
        echo "[i] Server is already running."
    else
        echo "[*] Starting server in background..."
        nohup ./$SERVER_NAME > "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
        sleep 1
        echo "[i] Server started."
    fi
}

function stop_server() {
    if is_server_running; then
        pid=$(cat "$PID_FILE")
        kill "$pid"
        echo "[🛑] Server stopped."
    else
        echo "[i] Server was not running."
    fi
}

function change_port() {
    echo "کدام پورت را می‌خواهید تغییر دهید؟"
    echo "1. TCP"
    echo "2. UDP"
    echo "3. هر دو"
    read -p "انتخاب شما (1/2/3): " port_choice

    if [ -f $CONFIG_FILE ]; then
        case $port_choice in
            1)
                read -p "پورت جدید TCP را وارد کنید: " newtcp
                if [[ $newtcp =~ ^[0-9]+$ ]]; then
                    jq ".tcp_port = $newtcp" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
                    echo "TCP port changed to $newtcp."
                else
                    echo "پورت نامعتبر!"
                fi
                ;;
            2)
                read -p "پورت جدید UDP را وارد کنید: " newudp
                if [[ $newudp =~ ^[0-9]+$ ]]; then
                    jq ".udp_port = $newudp" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
                    echo "UDP port changed to $newudp."
                else
                    echo "پورت نامعتبر!"
                fi
                ;;
            3)
                read -p "پورت جدید TCP را وارد کنید: " newtcp
                read -p "پورت جدید UDP را وارد کنید: " newudp
                if [[ $newtcp =~ ^[0-9]+$ && $newudp =~ ^[0-9]+$ ]]; then
                    jq ".tcp_port = $newtcp | .udp_port = $newudp" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
                    echo "TCP port changed to $newtcp."
                    echo "UDP port changed to $newudp."
                else
                    echo "پورت نامعتبر!"
                fi
                ;;
            *)
                echo "انتخاب نامعتبر!"
                ;;
        esac
        restart_server
    else
        echo "config.json پیدا نشد!"
    fi
}

function create_config() {
    echo "Generating new config..."
    
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    # Generate UUIDs
    CONFIG_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "config-$(date +%s)")
    SESSION_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "session-$(date +%s)")
    
    cat > "$CONFIG_FILE" << EOF
{
  "server": "$SERVER_IP",
  "tcp_port": 3077,
  "udp_port": 3076,
  "config_id": "$CONFIG_ID",
  "session_id": "$SESSION_ID",
  "protocol": "novaguard-v1",
  "encryption": "chacha20-poly1305",
  "version": "1.0.0",
  "certfile": "novaguard.crt",
  "keyfile": "novaguard.key"
}
EOF
    echo "Config generated: $CONFIG_FILE"
}

function is_port_listening() {
    local port=$1
    if [ -z "$port" ]; then
        return 1
    fi
    if sudo lsof -i :$port | grep LISTEN >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

function show_menu() {
    clear
    echo ""
    echo "+--------------------------------------+"
    echo "|         NOVAGUARD SERVER MENU        |"
    echo "+--------------------------------------+"
    echo "| 1. Create new config                |"
    echo "| 2. Delete a config                  |"
    echo "| 3. Show all configs                 |"
    echo "| 4. Restart server                   |"
    echo "| 5. Change server port               |"
    echo "| 6. Exit                             |"
    echo "| 7. Stop server                      |"
    echo "| 8. Check server internet access     |"
    echo "| 9. Start server                     |"
    echo "|10. Full uninstall & cleanup         |"
    echo "+--------------------------------------+"
    echo ""
}

function restart_server() {
    stop_server
    start_server_bg
}

function check_internet() {
    echo "Checking internet connectivity..."
    if ping -c 2 8.8.8.8 >/dev/null 2>&1; then
        echo "[OK] Server has internet access."
    else
        echo "[FAIL] Server does NOT have internet access!"
    fi
    echo "Press Enter to return to menu..."
    read
}

function generate_connection_code() {
    if [ -f "$CONFIG_FILE" ]; then
        # Generate connection code using the Go server
        connection_code=$(./$SERVER_NAME --show-code 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "$connection_code"
            mkdir -p configs
            echo "$connection_code" >> "$HISTORY_FILE"
        else
            echo "[خطا] نتوانست کد اتصال تولید کند!"
        fi
    else
        echo "[خطا] فایل config.json یافت نشد!"
    fi
}

# --- ابتدای اسکریپت ---
# سوال برای راه‌اندازی سرور قبل از منو
if ! is_server_running; then
    read -p "آیا سرور راه‌اندازی شود؟ (Y/n): " startans
    if [[ -z "$startans" || "$startans" =~ ^[Yy]$ ]]; then
        stop_server
        start_server_bg
    fi
fi

while true; do
    show_menu
    read -p "Select an option [1-10]: " choice
    case $choice in
        1)
            stop_server
            start_server_bg
            sleep 2
            if is_port_listening "3077" || is_port_listening "3076"; then
                if [ ! -f "$CONFIG_FILE" ]; then
                    echo "No config.json found. Creating new config..."
                    create_config
                    # فقط اگر کانفیگ جدید ساخته شد، کد اتصال را نمایش بده
                    connection_code=$(generate_connection_code)
                    if [ ! -z "$connection_code" ]; then
                        echo "ng://$connection_code"
                    fi
                else
                    echo "Using existing config.json. کد اتصال نمایش داده نمی‌شود."
                fi
            else
                echo "[خطا] سرور روی پورت 3077 یا 3076 اجرا نشده است! کانفیگ ساخته نشد."
            fi
            read -p "Return to menu? (y/n): " back
            if [[ "$back" != "y" && "$back" != "Y" ]]; then
                echo "Exiting menu."
                exit 0
            fi
            ;;
        2)
            echo "Deleting a config..."
            read -p "Enter line number or config text to delete: " confline
            if [[ -f $HISTORY_FILE ]]; then
                grep -v "$confline" $HISTORY_FILE > $HISTORY_FILE.tmp && mv $HISTORY_FILE.tmp $HISTORY_FILE
                echo "Config deleted (if existed)."
            else
                echo "No configs saved."
            fi
            read -p "Press Enter to return to menu..."
            ;;
        3)
            echo "Saved configs list:"
            if [[ -f $HISTORY_FILE ]]; then
                nl -w2 -s'. ' $HISTORY_FILE
            else
                echo "No configs saved."
            fi
            read -p "Press Enter to return to menu..."
            ;;
        4)
            echo "Restarting server..."
            restart_server
            read -p "Press Enter to return to menu..."
            ;;
        5)
            change_port
            read -p "Press Enter to return to menu..."
            ;;
        6)
            echo "Exiting menu."
            exit 0
            ;;
        7)
            stop_server
            read -p "Press Enter to return to menu..."
            ;;
        8)
            check_internet
            ;;
        9)
            start_server_bg
            read -p "Press Enter to return to menu..."
            ;;
        10)
            full_cleanup
            ;;
        *)
            echo "Invalid option. Please select 1-10."
            sleep 2
            ;;
    esac
done 
