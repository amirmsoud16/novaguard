#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/novaguard-server"
SERVICE_FILE="novaguard.service"
SERVICE_NAME="novaguard"

echo -e "${GREEN}NovaGuard Server Installer${NC}"
echo "================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${YELLOW}Go is not installed. Installing Go...${NC}"
    
    # Detect OS and install Go
    if [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        apt update
        apt install -y golang-go
    elif [[ -f /etc/redhat-release ]]; then
        # CentOS/RHEL/Fedora
        yum install -y golang
    else
        echo -e "${RED}Unsupported OS. Please install Go manually.${NC}"
        exit 1
    fi
fi

# Check Go version
GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
REQUIRED_VERSION="1.21"

if [[ "$(printf '%s\n' "$REQUIRED_VERSION" "$GO_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]]; then
    echo -e "${RED}Go version $GO_VERSION is too old. Required: $REQUIRED_VERSION or later${NC}"
    exit 1
fi

echo -e "${GREEN}Go version $GO_VERSION detected${NC}"

# Create installation directory
echo "Creating installation directory..."
mkdir -p "$INSTALL_DIR"

# Copy files to installation directory
echo "Copying files..."
cp -r . "$INSTALL_DIR/"
cd "$INSTALL_DIR"

# Set permissions
chmod +x *.sh
chmod +x novaguard-server

# Generate certificate if not exists
if [[ ! -f "novaguard.crt" ]] || [[ ! -f "novaguard.key" ]]; then
    echo "Generating SSL certificate..."
    ./generate_cert.sh
fi

# Generate config if not exists
if [[ ! -f "config.json" ]]; then
    echo "Generating configuration..."
    ./manage.sh generate-config
fi

# Build the server
echo "Building server..."
./build.sh

# Install systemd service
echo "Installing systemd service..."
cp "$SERVICE_FILE" "/etc/systemd/system/"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"

# Create firewall rules
echo "Configuring firewall..."
if command -v ufw &> /dev/null; then
    # Ubuntu/Debian
    ufw allow 3077/tcp
    ufw allow 3076/udp
    echo -e "${GREEN}UFW rules added${NC}"
elif command -v firewall-cmd &> /dev/null; then
    # CentOS/RHEL/Fedora
    firewall-cmd --permanent --add-port=3077/tcp
    firewall-cmd --permanent --add-port=3076/udp
    firewall-cmd --reload
    echo -e "${GREEN}Firewalld rules added${NC}"
else
    echo -e "${YELLOW}No firewall detected. Please configure manually:${NC}"
    echo "  TCP Port: 3077"
    echo "  UDP Port: 3076"
fi

# Start the service
echo "Starting NovaGuard service..."
systemctl start "$SERVICE_NAME"

# Check if service is running
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${GREEN}NovaGuard service started successfully${NC}"
else
    echo -e "${RED}Failed to start NovaGuard service${NC}"
    systemctl status "$SERVICE_NAME"
    exit 1
fi

# Show connection code
echo ""
echo -e "${GREEN}Installation completed successfully!${NC}"
echo ""
echo "Connection Code:"
./novaguard-server --show-code
echo ""
echo "Service commands:"
echo "  Start:   systemctl start $SERVICE_NAME"
echo "  Stop:    systemctl stop $SERVICE_NAME"
echo "  Status:  systemctl status $SERVICE_NAME"
echo "  Logs:    journalctl -u $SERVICE_NAME -f"
echo ""
echo "Installation directory: $INSTALL_DIR" 