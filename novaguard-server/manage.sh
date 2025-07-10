#!/bin/bash

SERVER_NAME="novaguard-server"
PID_FILE="novaguard-server.pid"
LOG_FILE="novaguard-server.log"

function is_running() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

function start_server() {
    if is_running; then
        echo "Server is already running (PID: $(cat $PID_FILE))"
        return
    fi
    
    echo "Starting NovaGuard server..."
    nohup ./$SERVER_NAME > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    sleep 2
    
    if is_running; then
        echo "Server started successfully (PID: $(cat $PID_FILE))"
        echo "Log file: $LOG_FILE"
    else
        echo "Failed to start server"
        rm -f "$PID_FILE"
        exit 1
    fi
}

function stop_server() {
    if ! is_running; then
        echo "Server is not running"
        return
    fi
    
    pid=$(cat "$PID_FILE")
    echo "Stopping server (PID: $pid)..."
    kill "$pid"
    
    # Wait for server to stop
    for i in {1..10}; do
        if ! ps -p "$pid" > /dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    
    if ps -p "$pid" > /dev/null 2>&1; then
        echo "Force killing server..."
        kill -9 "$pid"
    fi
    
    rm -f "$PID_FILE"
    echo "Server stopped"
}

function restart_server() {
    echo "Restarting server..."
    stop_server
    sleep 2
    start_server
}

function status_server() {
    if is_running; then
        pid=$(cat "$PID_FILE")
        echo "Server is running (PID: $pid)"
        echo "Log file: $LOG_FILE"
        echo "Last 10 log lines:"
        tail -10 "$LOG_FILE" 2>/dev/null || echo "No log file found"
    else
        echo "Server is not running"
    fi
}

function show_logs() {
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        echo "No log file found"
    fi
}

function generate_config() {
    echo "Generating new config..."
    
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    # Generate UUIDs
    CONFIG_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "config-$(date +%s)")
    SESSION_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "session-$(date +%s)")
    
    cat > config.json << EOF
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
    
    echo "Config generated: config.json"
}

function show_connection_code() {
    if [ -f "config.json" ]; then
        echo "Current connection code:"
        ./$SERVER_NAME --show-code 2>/dev/null || echo "Run server to see connection code"
    else
        echo "No config.json found. Run 'generate-config' first."
    fi
}

case "$1" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        restart_server
        ;;
    status)
        status_server
        ;;
    logs)
        show_logs
        ;;
    generate-config)
        generate_config
        ;;
    show-code)
        show_connection_code
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|generate-config|show-code}"
        echo ""
        echo "Commands:"
        echo "  start           Start the server"
        echo "  stop            Stop the server"
        echo "  restart         Restart the server"
        echo "  status          Show server status"
        echo "  logs            Show live logs"
        echo "  generate-config Generate new config.json"
        echo "  show-code       Show connection code"
        exit 1
        ;;
esac 