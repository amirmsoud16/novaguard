#!/bin/bash

# اگر اسکریپت با نام novavpn اجرا شود یا به صورت مستقیم اجرا شود، منو را اجرا کن
SCRIPT_NAME=$(basename "$0")
if [[ "$SCRIPT_NAME" == "novavpn" || "$SCRIPT_NAME" == "nova.sh" ]]; then
    PROJECT_DIR="$(dirname "$0")"
    cd "$PROJECT_DIR"
    SERVER_NAME="novaguard-server"
    PID_FILE="novaguard-server.pid"
    LOG_FILE="novaguard-server.log"
    CONFIG_FILE="config.json"
    HISTORY_FILE="configs/history.txt"

    function is_server_running() {
        # بررسی PID file
        if [ -f "$PID_FILE" ]; then
            pid=$(cat "$PID_FILE")
            if ps -p "$pid" > /dev/null 2>&1; then
                return 0
            fi
        fi
        
        # بررسی process name
        if pgrep -f "novaguard-server" > /dev/null 2>&1; then
            return 0
        fi
        
        # بررسی systemd service
        if systemctl is-active --quiet novaguard 2>/dev/null; then
            return 0
        fi
        
        return 1
    }

    function get_server_pid() {
        # ابتدا از PID file
        if [ -f "$PID_FILE" ]; then
            pid=$(cat "$PID_FILE")
            if ps -p "$pid" > /dev/null 2>&1; then
                echo "$pid"
                return
            fi
        fi
        
        # سپس از process name
        pgrep -f "novaguard-server" | head -1
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
        # مقداردهی پورت‌ها
        local tcp_port=3077
        local udp_port=3076
        read -p "پورت TCP را وارد کنید (پیش‌فرض: 3077): " input_tcp
        if [[ $input_tcp =~ ^[0-9]+$ ]]; then
            tcp_port=$input_tcp
        fi
        read -p "پورت UDP را وارد کنید (پیش‌فرض: 3076): " input_udp
        if [[ $input_udp =~ ^[0-9]+$ ]]; then
            udp_port=$input_udp
        fi
        # ساخت config.json با هر دو پورت
        cat > config.json << EOF
{
  "server": "$(hostname -I | awk '{print $1}')",
  "tcp_port": $tcp_port,
  "udp_port": $udp_port,
  "protocol": "novaguard-v1",
  "encryption": "chacha20-poly1305",
  "version": "1.0.0",
  "certfile": "novaguard.crt",
  "keyfile": "novaguard.key"
}
EOF
        echo "Config generated: config.json (TCP: $tcp_port, UDP: $udp_port)"
        echo "\nتوجه: کلاینت می‌تواند بین TCP و UDP سوییچ کند."
    }

    function is_port_listening() {
        local port=$1
        if [ -z "$port" ]; then
            return 1
        fi
        # بررسی TCP و UDP
        if sudo lsof -iTCP:$port -sTCP:LISTEN 2>/dev/null | grep LISTEN >/dev/null 2>&1; then
            return 0
        fi
        if sudo lsof -iUDP:$port 2>/dev/null | grep UDP >/dev/null 2>&1; then
            return 0
        fi
        return 1
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
        echo "|11. Show server status               |"
        echo "+--------------------------------------+"
        echo ""
    }

    function show_server_status() {
        echo "=== NovaGuard Server Status ==="
        if is_server_running; then
            echo "Status: Running"
            pid=$(get_server_pid)
            if [ ! -z "$pid" ]; then
                echo "PID: $pid"
                echo "Memory Usage: $(ps -o rss= -p $pid 2>/dev/null | awk '{print $1/1024 " MB"}')"
            fi
            echo "Ports:"
            if is_port_listening "3077"; then
                echo "  TCP Port 3077: Active"
            else
                echo "  TCP Port 3077: Inactive"
            fi
            if is_port_listening "3076"; then
                echo "  UDP Port 3076: Active"
            else
                echo "  UDP Port 3076: Inactive"
            fi
            if [ -f "$CONFIG_FILE" ]; then
                echo "Config: Loaded"
                echo "Server IP: $(jq -r '.server' "$CONFIG_FILE" 2>/dev/null || echo "Unknown")"
            else
                echo "Config: Not found"
            fi
        else
            echo "Status: Stopped"
            echo "Ports: Inactive"
            echo "Config: Not loaded"
        fi
        echo "================================"
        read -p "Press Enter to return to menu..."
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

    function full_cleanup() {
        NOVAGUARD_ID=3315
        INSTALL_DIR="/usr/local/novaguard-$NOVAGUARD_ID"
        SERVICE_FILE="novaguard-$NOVAGUARD_ID.service"
        SERVICE_NAME="novaguard-$NOVAGUARD_ID"
        SYMLINK_BIN="/usr/local/bin/novavpn-$NOVAGUARD_ID"
        echo "⚠️  هشدار: این عملیات همه فایل‌ها، سرویس‌ها و منوی novavpn-$NOVAGUARD_ID را حذف می‌کند!"
        read -p "آیا مطمئن هستید؟ (yes/NO): " confirm
        if [[ "$confirm" == "yes" ]]; then
            # توقف و حذف سرویس systemd
            if systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
                systemctl stop $SERVICE_NAME 2>/dev/null
            fi
            if systemctl is-enabled --quiet $SERVICE_NAME 2>/dev/null; then
                systemctl disable $SERVICE_NAME 2>/dev/null
            fi
            if [ -f "/etc/systemd/system/$SERVICE_FILE" ]; then
                rm -f /etc/systemd/system/$SERVICE_FILE
                systemctl daemon-reload
            fi
            # حذف symlink novavpn
            if [ -L "$SYMLINK_BIN" ]; then
                rm -f "$SYMLINK_BIN"
            fi
            # حذف کامل دایرکتوری نصب
            if [ -d "$INSTALL_DIR" ]; then
                rm -rf "$INSTALL_DIR"
            fi
            echo "حذف کامل پروتوکل با موفقیت انجام شد ✅"
            exit 0
        else
            echo "لغو شد."
        fi
        read -p "Press Enter to return to menu..."
    }

    # اگر سرور اجرا نمی‌شود، آن را در پس‌زمینه اجرا کن
    if ! is_server_running; then
        start_server_bg
    fi

    # اجرای منو
    while true; do
        show_menu
        read -p "Select an option [1-11]: " choice
        case $choice in
            1)
                stop_server
                start_server_bg
                sleep 2
                if is_port_listening "3077" || is_port_listening "3076"; then
                    echo "Creating new config..."
                    create_config
                    connection_code=$(generate_connection_code)
                    if [ ! -z "$connection_code" ]; then
                        echo "ng://$connection_code"
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
            11)
                show_server_status
                ;;
            *)
                echo "Invalid option. Please select 1-11."
                sleep 2
                ;;
        esac
    done
    exit 0
fi

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
    # مقداردهی پورت‌ها
    local tcp_port=3077
    local udp_port=3076
    read -p "پورت TCP را وارد کنید (پیش‌فرض: 3077): " input_tcp
    if [[ $input_tcp =~ ^[0-9]+$ ]]; then
        tcp_port=$input_tcp
    fi
    read -p "پورت UDP را وارد کنید (پیش‌فرض: 3076): " input_udp
    if [[ $input_udp =~ ^[0-9]+$ ]]; then
        udp_port=$input_udp
    fi
    # ساخت config.json با هر دو پورت
    cat > config.json << EOF
{
  "server": "$(hostname -I | awk '{print $1}')",
  "tcp_port": $tcp_port,
  "udp_port": $udp_port,
  "protocol": "novaguard-v1",
  "encryption": "chacha20-poly1305",
  "version": "1.0.0",
  "certfile": "novaguard.crt",
  "keyfile": "novaguard.key"
}
EOF
    echo "Config generated: config.json (TCP: $tcp_port, UDP: $udp_port)"
    echo "\nتوجه: کلاینت می‌تواند بین TCP و UDP سوییچ کند."
}

function is_port_listening() {
    local port=$1
    if [ -z "$port" ]; then
        return 1
    fi
    # بررسی TCP و UDP
    if sudo lsof -iTCP:$port -sTCP:LISTEN 2>/dev/null | grep LISTEN >/dev/null 2>&1; then
        return 0
    fi
    if sudo lsof -iUDP:$port 2>/dev/null | grep UDP >/dev/null 2>&1; then
        return 0
    fi
    return 1
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
    echo "|11. Show server status               |"
    echo "+--------------------------------------+"
    echo ""
}

function show_server_status() {
    echo "=== NovaGuard Server Status ==="
    if is_server_running; then
        echo "Status: Running"
        if [ -f "$PID_FILE" ]; then
            pid=$(cat "$PID_FILE")
            echo "PID: $pid"
            echo "Memory Usage: $(ps -o rss= -p $pid 2>/dev/null | awk '{print $1/1024 " MB"}')"
        fi
        echo "Ports:"
        if is_port_listening "3077"; then
            echo "  TCP Port 3077: Active"
        else
            echo "  TCP Port 3077: Inactive"
        fi
        if is_port_listening "3076"; then
            echo "  UDP Port 3076: Active"
        else
            echo "  UDP Port 3076: Inactive"
        fi
        if [ -f "$CONFIG_FILE" ]; then
            echo "Config: Loaded"
            echo "Server IP: $(jq -r '.server' "$CONFIG_FILE" 2>/dev/null || echo "Unknown")"
        else
            echo "Config: Not found"
        fi
    else
        echo "Status: Stopped"
        echo "Ports: Inactive"
        echo "Config: Not loaded"
    fi
    echo "================================"
    read -p "Press Enter to return to menu..."
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
    read -p "Select an option [1-11]: " choice
    case $choice in
        1)
            stop_server
            start_server_bg
            sleep 2
            if is_port_listening "3077" || is_port_listening "3076"; then
                echo "Creating new config..."
                create_config
                connection_code=$(generate_connection_code)
                if [ ! -z "$connection_code" ]; then
                    echo "ng://$connection_code"
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
        11)
            show_server_status
            ;;
        *)
            echo "Invalid option. Please select 1-11."
            sleep 2
            ;;
    esac
done 
