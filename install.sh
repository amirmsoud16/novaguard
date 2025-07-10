#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GITHUB_REPO="https://github.com/amirmsoud16/novaguard.git"
INSTALL_DIR="/opt/novaguard-server"
SERVICE_FILE="novaguard.service"
SERVICE_NAME="novaguard"
TEMP_DIR="/tmp/novaguard-install"

echo -e "${GREEN}NovaGuard Server Installer${NC}"
echo "================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Function to check internet connectivity
check_internet() {
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "${RED}No internet connection detected${NC}"
        exit 1
    fi
}

# Function to install prerequisites
install_prerequisites() {
    echo -e "${BLUE}Installing prerequisites...${NC}"
    
    # Detect OS and install packages
    if [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        apt update
        apt install -y git curl wget jq golang-go
    elif [[ -f /etc/redhat-release ]]; then
        # CentOS/RHEL/Fedora
        yum install -y git curl wget jq golang
    else
        echo -e "${YELLOW}Unsupported OS. Please install git, curl, wget, jq, and Go manually.${NC}"
        exit 1
    fi
}

# Function to download from GitHub
download_from_github() {
    echo -e "${BLUE}Downloading NovaGuard from GitHub...${NC}"
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        echo -e "${YELLOW}Git is not installed. Installing prerequisites...${NC}"
        install_prerequisites
    fi
    
    # Create temp directory
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Clone repository
    echo "Cloning repository: $GITHUB_REPO"
    if git clone "$GITHUB_REPO" .; then
        echo -e "${GREEN}Repository downloaded successfully${NC}"
    else
        echo -e "${RED}Failed to download repository${NC}"
        exit 1
    fi
}

# Function to install Go if needed
install_go() {
    if ! command -v go &> /dev/null; then
        echo -e "${YELLOW}Go is not installed. Installing Go...${NC}"
        install_prerequisites
    fi

    # Check Go version
    GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    REQUIRED_VERSION="1.21"

    if [[ "$(printf '%s\n' "$REQUIRED_VERSION" "$GO_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]]; then
        echo -e "${RED}Go version $GO_VERSION is too old. Required: $REQUIRED_VERSION or later${NC}"
        exit 1
    fi

    echo -e "${GREEN}Go version $GO_VERSION detected${NC}"
}

# Function to install NovaGuard
install_novaguard() {
    echo -e "${BLUE}Installing NovaGuard Server...${NC}"
    
    # Create installation directory
    echo "Creating installation directory..."
    mkdir -p "$INSTALL_DIR"

    # Copy files to installation directory
    echo "Copying files..."
    cp -r . "$INSTALL_DIR/"
    cd "$INSTALL_DIR"

    # Ensure all necessary files are present
    if [[ ! -f "main.go" ]]; then
        echo -e "${RED}Error: main.go not found in repository${NC}"
        exit 1
    fi
    
    if [[ ! -f "go.mod" ]]; then
        echo -e "${RED}Error: go.mod not found in repository${NC}"
        exit 1
    fi

    # Set permissions
    chmod +x *.sh
    if [[ -f "novaguard-server" ]]; then
        chmod +x novaguard-server
    fi

    # Generate SSL certificate
    echo "Generating SSL certificate..."
    ./generate_cert.sh

    # Generate configuration
    echo "Generating configuration..."
    
    # Auto-detect server IP
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
    echo "Server IP detected: $SERVER_IP"

    # Build the server
    echo "Building server..."
    
    # Download and tidy dependencies first
    echo "Downloading Go dependencies..."
    go mod download
    go mod tidy
    
    # Then build
    ./build.sh
}

# Function to setup systemd service
setup_systemd() {
    echo "Installing systemd service..."
    
    # Remove old service file if exists
    if [[ -f "/etc/systemd/system/$SERVICE_FILE" ]]; then
        echo "Removing old service file..."
        rm -f "/etc/systemd/system/$SERVICE_FILE"
    fi
    
    # Install new service
    cp "$SERVICE_FILE" "/etc/systemd/system/"
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    echo "Systemd service installed successfully"
}

# Function to configure firewall
configure_firewall() {
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
}

# Function to start service
start_service() {
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
}

# Function to show installation info
show_info() {
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
    echo ""
    echo "To use the interactive menu:"
    echo "  cd $INSTALL_DIR"
    echo "  ./nova.sh"
}

# Function to cleanup
cleanup() {
    echo "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Main installation process
main() {
    # Check internet connectivity
    check_internet
    
    # Download from GitHub
    download_from_github
    
    # Install Go if needed
    install_go
    
    # Install NovaGuard
    install_novaguard
    
    # Setup systemd service
    setup_systemd
    
    # Configure firewall
    configure_firewall
    
    # Start service
    start_service
    
    # Show installation info
    show_info
    
    # Cleanup
    cleanup
}

# Run main function
main 
