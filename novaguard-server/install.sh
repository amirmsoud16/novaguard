#!/bin/bash

set -e

# تنظیمات رنگ برای خروجی
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# تنظیمات اصلی
GITHUB_REPO="https://github.com/amirmsoud16/novaguard.git"
RAW_REPO="https://raw.githubusercontent.com/amirmsoud16/novaguard/main/novaguard-server"
INSTALL_DIR="/usr/local/novaguard-server"
SERVICE_FILE="novaguard.service"
SERVICE_NAME="novaguard"
TEMP_DIR="/tmp/novaguard-install"

echo -e "${GREEN}NovaGuard Server Installer${NC}"
echo "================================"

# بررسی دسترسی root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}این اسکریپت باید با دسترسی root اجرا شود (sudo)${NC}"
   exit 1
fi

# تابع بررسی اتصال اینترنت
check_internet() {
    echo -e "${BLUE}بررسی اتصال اینترنت...${NC}"
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "${RED}اتصال اینترنت یافت نشد${NC}"
        exit 1
    fi
    echo -e "${GREEN}اتصال اینترنت برقرار است${NC}"
}

# تابع نصب پیش‌نیازها
install_prerequisites() {
    echo -e "${BLUE}نصب پیش‌نیازها...${NC}"
    
    # تشخیص سیستم عامل و نصب پکیج‌ها
    if [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        apt update
        apt install -y git curl wget jq golang-go
    elif [[ -f /etc/redhat-release ]]; then
        # CentOS/RHEL/Fedora
        yum install -y git curl wget jq golang
    else
        echo -e "${YELLOW}سیستم عامل پشتیبانی نشده. لطفاً git، curl، wget، jq و Go را دستی نصب کنید.${NC}"
        exit 1
    fi
}

# تابع دانلود از GitHub
download_from_github() {
    echo -e "${BLUE}دانلود NovaGuard از GitHub...${NC}"
    
    # بررسی نصب بودن git
    if ! command -v git &> /dev/null; then
        echo -e "${YELLOW}Git نصب نیست. نصب پیش‌نیازها...${NC}"
        install_prerequisites
    fi
    
    # ساخت دایرکتوری موقت
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # کلون کردن مخزن
    echo "کلون کردن مخزن: $GITHUB_REPO"
    if git clone "$GITHUB_REPO" .; then
        echo -e "${GREEN}مخزن با موفقیت دانلود شد${NC}"
    else
        echo -e "${RED}خطا در دانلود مخزن${NC}"
        exit 1
    fi
}

# تابع بررسی و نصب Go
install_go() {
    if ! command -v go &> /dev/null; then
        echo -e "${YELLOW}Go نصب نیست. نصب Go...${NC}"
        install_prerequisites
    fi

    # بررسی نسخه Go
    GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    REQUIRED_VERSION="1.21"

    if [[ "$(printf '%s\n' "$REQUIRED_VERSION" "$GO_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]]; then
        echo -e "${RED}نسخه Go $GO_VERSION قدیمی است. نیاز به نسخه $REQUIRED_VERSION یا بالاتر${NC}"
        exit 1
    fi

    echo -e "${GREEN}نسخه Go $GO_VERSION شناسایی شد${NC}"
}

# تابع نصب NovaGuard
install_novaguard() {
    echo -e "${BLUE}نصب NovaGuard Server...${NC}"
    
    # حذف دایرکتوری نصب قبلی در صورت وجود
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "حذف نصب قبلی..."
        rm -rf "$INSTALL_DIR"
    fi
    
    # ساخت دایرکتوری نصب
    echo "ساخت دایرکتوری نصب..."
    mkdir -p "$INSTALL_DIR"

    # کپی فایل‌ها به دایرکتوری نصب
    echo "کپی فایل‌ها..."
    if [[ -d "novaguard-server" ]]; then
        cp -r novaguard-server/* "$INSTALL_DIR/"
    else
        cp -r . "$INSTALL_DIR/"
    fi
    cd "$INSTALL_DIR"

    # بررسی وجود فایل‌های ضروری
    if [[ ! -f "main.go" ]]; then
        echo -e "${RED}خطا: main.go در مخزن یافت نشد${NC}"
        exit 1
    fi
    
    if [[ ! -f "go.mod" ]]; then
        echo -e "${RED}خطا: go.mod در مخزن یافت نشد${NC}"
        exit 1
    fi

    # تنظیم مجوزها
    chmod +x *.sh
    if [[ -f "novaguard-server" ]]; then
        chmod +x novaguard-server
    fi

    # تولید گواهی SSL
    echo "تولید گواهی SSL..."
    if [[ -f "generate_cert.sh" ]]; then
        ./generate_cert.sh
    else
        echo -e "${YELLOW}فایل generate_cert.sh یافت نشد. گواهی SSL تولید نمی‌شود.${NC}"
    fi

    # تولید کانفیگ
    echo "تولید کانفیگ..."
    
    # تشخیص خودکار IP سرور
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}' 2>/dev/null || echo "0.0.0.0")
    
    cat > config.json << EOF
{
  "server": "$SERVER_IP",
  "tcp_port": 3077,
  "udp_port": 3076,
  "config_id": "novaguard-config-$(date +%s)",
  "session_id": "session-$(date +%s)",
  "protocol": "novaguard-v1",
  "encryption": "chacha20-poly1305",
  "version": "1.0.0",
  "certfile": "novaguard.crt",
  "keyfile": "novaguard.key"
}
EOF
    echo "IP سرور تشخیص داده شد: $SERVER_IP"

    # ساخت سرور
    echo "ساخت سرور..."
    
    # دانلود و مرتب کردن وابستگی‌ها
    echo "دانلود وابستگی‌های Go..."
    
    # حذف فایل خراب go.sum در صورت وجود
    if [[ -f "go.sum" ]]; then
        echo "حذف فایل خراب go.sum..."
        rm -f go.sum
    fi
    
    # بازسازی go.sum
    go mod download
    go mod tidy
    
    # ساخت پروژه
    if [[ -f "build.sh" ]]; then
        ./build.sh
    else
        go build -o novaguard-server main.go
    fi
}

# تابع نصب سرویس systemd
setup_systemd() {
    echo "نصب سرویس systemd..."
    
    # حذف فایل سرویس قدیمی در صورت وجود
    if [[ -f "/etc/systemd/system/$SERVICE_FILE" ]]; then
        echo "حذف فایل سرویس قدیمی..."
        rm -f "/etc/systemd/system/$SERVICE_FILE"
    fi
    
    # توقف سرویس قبلی در صورت فعال بودن
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "توقف سرویس قبلی..."
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    fi
    
    # نصب سرویس جدید
    cp "$SERVICE_FILE" "/etc/systemd/system/"
    
    # اطمینان از مجوزهای صحیح
    chmod 644 "/etc/systemd/system/$SERVICE_FILE"
    
    # بارگذاری مجدد systemd
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    echo "سرویس systemd با موفقیت نصب شد"
}

# تابع تنظیم فایروال
configure_firewall() {
    echo "تنظیم فایروال..."
    if command -v ufw &> /dev/null; then
        # Ubuntu/Debian
        ufw allow 3077/tcp
        ufw allow 3076/udp
        echo -e "${GREEN}قوانین UFW اضافه شد${NC}"
    elif command -v firewall-cmd &> /dev/null; then
        # CentOS/RHEL/Fedora
        firewall-cmd --permanent --add-port=3077/tcp
        firewall-cmd --permanent --add-port=3076/udp
        firewall-cmd --reload
        echo -e "${GREEN}قوانین Firewalld اضافه شد${NC}"
    else
        echo -e "${YELLOW}فایروال شناسایی نشد. لطفاً دستی تنظیم کنید:${NC}"
        echo "  پورت TCP: 3077"
        echo "  پورت UDP: 3076"
    fi
}

# تابع راه‌اندازی سرویس
start_service() {
    echo "راه‌اندازی سرویس NovaGuard..."
    systemctl start "$SERVICE_NAME"

    # بررسی وضعیت سرویس
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}سرویس NovaGuard با موفقیت راه‌اندازی شد${NC}"
    else
        echo -e "${RED}خطا در راه‌اندازی سرویس NovaGuard${NC}"
        systemctl status "$SERVICE_NAME"
        exit 1
    fi
}

# تابع نمایش اطلاعات نصب
show_info() {
    echo ""
    echo -e "${GREEN}نصب با موفقیت انجام شد!${NC}"
    echo ""
    # حذف نمایش کد اتصال
    echo "دستورات سرویس:"
    echo "  شروع:   systemctl start $SERVICE_NAME"
    echo "  توقف:    systemctl stop $SERVICE_NAME"
    echo "  وضعیت:  systemctl status $SERVICE_NAME"
    echo "  لاگ:    journalctl -u $SERVICE_NAME -f"
    echo ""
    echo "دایرکتوری نصب: $INSTALL_DIR"
    echo ""
    echo "برای استفاده از منوی تعاملی:"
    echo "  cd $INSTALL_DIR"
    echo "  ./nova.sh"
}

# تابع پاک‌سازی
cleanup() {
    echo "پاک‌سازی فایل‌های موقت..."
    rm -rf "$TEMP_DIR"
}

# فرآیند اصلی نصب
main() {
    # بررسی اتصال اینترنت
    check_internet
    
    # دانلود از GitHub
    download_from_github
    
    # نصب Go در صورت نیاز
    install_go
    
    # نصب NovaGuard
    install_novaguard
    
    # نصب سرویس systemd
    setup_systemd
    
    # تنظیم فایروال
    configure_firewall
    
    # راه‌اندازی سرویس
    start_service
    
    # نمایش اطلاعات نصب
    show_info
    
    # پاک‌سازی
    cleanup
}

# اجرای تابع اصلی
main 
