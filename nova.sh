#!/bin/bash

PROJECT_DIR="$(dirname "$0")"
cd "$PROJECT_DIR"
export PYTHONPATH="$PROJECT_DIR:$PYTHONPATH"
CONFIG_DIR="configs"
SERVER_SCRIPT="server.py"
CONFIG_FILE="config.json"
HISTORY_FILE="$CONFIG_DIR/history.txt"

function is_server_running() {
    pgrep -f $SERVER_SCRIPT > /dev/null
}

function start_server_bg() {
    if is_server_running; then
        echo "[i] Server is already running."
    else
        echo "[*] Starting server in background..."
        nohup python3 $SERVER_SCRIPT > server.log 2>&1 &
        sleep 1
        echo "[i] Server started."
    fi
}

function stop_server() {
    if is_server_running; then
        pkill -f $SERVER_SCRIPT
        echo "[🛑] Server stopped."
    else
        echo "[i] Server was not running."
    fi
}

function change_port() {
    read -p "Enter new port: " newport
    if [[ ! $newport =~ ^[0-9]+$ ]]; then
        echo "Invalid port!"
        return
    fi
    if [ -f $CONFIG_FILE ]; then
        jq ".port = $newport" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
        echo "Port changed to $newport."
        restart_server
    else
        echo "config.json not found!"
    fi
}

function create_config() {
CONFIG_PATH="$PROJECT_DIR/config.json"
mkdir -p "$(dirname "$CONFIG_PATH")"
> "$CONFIG_PATH"
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
  "tcp_port": $TCP_PORT,
  "udp_port": $UDP_PORT,
  "config_id": "$CONFIG_ID",
  "certfile": "/root/novaguard/novaguard.crt",
  "keyfile": "/root/novaguard/novaguard.key",
  "protocol": "novaguard-v1",
  "version": "1.0.0",
  "session_id": "$SESSION_ID"
}
EOF
}

function is_port_listening() {
    local port=$1
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
    echo "| 8. Check server internet access    |"
    echo "| 9. Start server                    |"
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

# --- ابتدای اسکریپت ---
# سوال برای راه‌اندازی سرور قبل از منو
if ! pgrep -f $SERVER_SCRIPT > /dev/null; then
    read -p "آیا سرور راه‌اندازی شود؟ (Y/n): " startans
    if [[ -z "$startans" || "$startans" =~ ^[Yy]$ ]]; then
        start_server_bg
    fi
fi

while true; do
    show_menu
    read -p "Select an option [1-9]: " choice
    case $choice in
        1)
            start_server_bg
            sleep 2
            tcp_port=$(jq -r '.tcp_port' "$PROJECT_DIR/config.json" 2>/dev/null || echo 8443)
            udp_port=$(jq -r '.udp_port' "$PROJECT_DIR/config.json" 2>/dev/null || echo 1195)
            if is_port_listening "$tcp_port" || is_port_listening "$udp_port"; then
                if [ ! -f "$PROJECT_DIR/config.json" ]; then
                    echo "No config.json found. Creating new config..."
                    create_config
                else
                    echo "Using existing config.json for ng:// generation."
                fi
                CONFIG_PATH="$PROJECT_DIR/config.json"
                # ساخت کد ng:// فقط با bash/jq/openssl
                host=$(jq -r '.host' "$CONFIG_PATH")
                tcp_port=$(jq -r '.tcp_port' "$CONFIG_PATH")
                udp_port=$(jq -r '.udp_port' "$CONFIG_PATH")
                config_id=$(jq -r '.config_id' "$CONFIG_PATH")
                protocol=$(jq -r '.protocol' "$CONFIG_PATH")
                certfile=$(jq -r '.certfile' "$CONFIG_PATH")
                fingerprint=$(openssl x509 -in "$certfile" -noout -fingerprint -sha256 | cut -d'=' -f2 | tr '[:lower:]' '[:upper:]')
                json=$(jq -n \
                  --arg server "$host" \
                  --argjson tcp_port "$tcp_port" \
                  --argjson udp_port "$udp_port" \
                  --arg config_id "$config_id" \
                  --arg fingerprint "$fingerprint" \
                  --arg protocol "$protocol" \
                  '{server: $server, tcp_port: $tcp_port, udp_port: $udp_port, config_id: $config_id, fingerprint: $fingerprint, protocol: $protocol}'
                )
                b64=$(echo -n "$json" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
                echo "ng://$b64"
                mkdir -p $CONFIG_DIR
                echo "ng://$b64" >> $HISTORY_FILE
            else
                echo "[خطا] سرور روی پورت $tcp_port یا $udp_port اجرا نشده است! کانفیگ ساخته نشد."
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
            echo "Exiting..."
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
        *)
            echo "Invalid option!"
            read -p "Press Enter to return to menu..."
            ;;
    esac
done 
