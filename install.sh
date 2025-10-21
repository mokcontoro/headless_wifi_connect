#!/bin/bash
# Installation Script for Headless WiFi Connect
# For Raspberry Pi 5 with Bookworm OS

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation paths
INSTALL_DIR="/opt/headless_wifi_connect"
BIN_DIR="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}  Headless WiFi Connect Installer   ${NC}"
echo -e "${BLUE}  Raspberry Pi 5 Bookworm OS        ${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Please run: sudo bash install.sh"
    exit 1
fi

# Check if running on Raspberry Pi
if [ ! -f /proc/device-tree/model ] || ! grep -qi "Raspberry Pi" /proc/device-tree/model; then
    echo -e "${YELLOW}WARNING: This script is designed for Raspberry Pi${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for Bookworm (Debian 12) or newer
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "${GREEN}Detected OS:${NC} $PRETTY_NAME (Debian $VERSION_ID)"

    # Check if version is at least Debian 12
    if [ -n "$VERSION_ID" ] && [ "$VERSION_ID" -lt "12" ]; then
        echo -e "${YELLOW}WARNING: This script is designed for Debian 12 (Bookworm) or newer${NC}"
        echo "Your version: $PRETTY_NAME"
        echo -e "${YELLOW}NetworkManager may not be available on older versions.${NC}"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    elif [ -n "$VERSION_ID" ] && [ "$VERSION_ID" -gt "12" ]; then
        echo -e "${GREEN}Running Debian $VERSION_ID (newer than Bookworm). This should work fine.${NC}"
    fi
fi

echo -e "${GREEN}[1/7] Checking dependencies...${NC}"

# Check for NetworkManager
if ! command -v nmcli &> /dev/null; then
    echo -e "${RED}ERROR: NetworkManager not found${NC}"
    echo "Installing NetworkManager..."
    apt-get update
    apt-get install -y network-manager
fi

# Check for Python 3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}ERROR: Python 3 not found${NC}"
    exit 1
fi

echo -e "${GREEN}[2/7] Installing required packages...${NC}"

# Update package list
apt-get update

# Install required packages
apt-get install -y \
    python3-flask \
    python3-pip \
    dnsmasq \
    iptables

echo -e "${GREEN}[3/7] Creating installation directories...${NC}"

# Create installation directory
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/wifi_portal"
mkdir -p "$INSTALL_DIR/wifi_portal/templates"
mkdir -p "$INSTALL_DIR/scripts"
mkdir -p "$INSTALL_DIR/systemd"

echo -e "${GREEN}[4/7] Copying files...${NC}"

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Copy project files
cp -r "$SCRIPT_DIR/wifi_portal/"* "$INSTALL_DIR/wifi_portal/"
cp -r "$SCRIPT_DIR/scripts/"* "$INSTALL_DIR/scripts/"
cp "$SCRIPT_DIR/setup_ap.sh" "$INSTALL_DIR/"

# Copy scripts to bin directory
cp "$INSTALL_DIR/setup_ap.sh" "$BIN_DIR/setup_ap.sh"
cp "$INSTALL_DIR/scripts/check_wifi.sh" "$BIN_DIR/check_wifi.sh"
cp "$INSTALL_DIR/scripts/configure_wifi.sh" "$BIN_DIR/configure_wifi.sh"

# Make scripts executable
chmod +x "$BIN_DIR/setup_ap.sh"
chmod +x "$BIN_DIR/check_wifi.sh"
chmod +x "$BIN_DIR/configure_wifi.sh"
chmod +x "$INSTALL_DIR/wifi_portal/app.py"

echo -e "${GREEN}[5/7] Installing systemd services...${NC}"

# Copy systemd service files
cp "$SCRIPT_DIR/systemd/wifi-portal.service" "$SYSTEMD_DIR/"
cp "$SCRIPT_DIR/systemd/wifi-check.service" "$SYSTEMD_DIR/"

# Reload systemd
systemctl daemon-reload

# Enable services
systemctl enable wifi-portal.service
systemctl enable wifi-check.service

echo -e "${GREEN}[6/7] Configuring system...${NC}"

# Ensure NetworkManager is enabled and started
systemctl enable NetworkManager
systemctl start NetworkManager

# Disable wpa_supplicant if it's running (conflicts with NetworkManager)
if systemctl is-active --quiet wpa_supplicant; then
    echo "Disabling wpa_supplicant (using NetworkManager instead)..."
    systemctl stop wpa_supplicant
    systemctl disable wpa_supplicant
fi

# Configure dnsmasq for captive portal
if [ ! -f /etc/dnsmasq.d/captive-portal.conf ]; then
    cat > /etc/dnsmasq.d/captive-portal.conf << 'EOF'
# Captive Portal Configuration
address=/#/192.168.4.1
EOF
fi

# Restart dnsmasq if running
if systemctl is-active --quiet dnsmasq; then
    systemctl restart dnsmasq
fi

echo -e "${GREEN}[7/7] Starting services...${NC}"

# Start the services
systemctl start wifi-portal.service
systemctl start wifi-check.service

# Wait a moment for services to initialize
sleep 2

# Check service status
if systemctl is-active --quiet wifi-portal.service && \
   systemctl is-active --quiet wifi-check.service; then
    echo ""
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}  Installation Successful!          ${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo ""
    echo -e "${BLUE}Services Status:${NC}"
    echo -e "  Portal Service: ${GREEN}Running${NC}"
    echo -e "  Monitor Service: ${GREEN}Running${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. The system will automatically create a WiFi hotspot"
    echo "2. Look for a network named 'RaspiCam-Setup-XXXX'"
    echo "3. Connect with password: 'raspberrypi'"
    echo "4. The configuration portal will open automatically"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "  View portal logs:   sudo journalctl -u wifi-portal -f"
    echo "  View monitor logs:  sudo journalctl -u wifi-check -f"
    echo "  Restart services:   sudo systemctl restart wifi-portal wifi-check"
    echo "  Manual AP setup:    sudo setup_ap.sh"
    echo "  Configure WiFi:     sudo configure_wifi.sh SSID PASSWORD"
    echo ""
    echo -e "${YELLOW}A reboot is recommended to ensure all services start correctly.${NC}"
    echo ""
    read -p "Reboot now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Rebooting..."
        reboot
    else
        echo "Please reboot manually when ready: sudo reboot"
    fi
else
    echo ""
    echo -e "${RED}=====================================${NC}"
    echo -e "${RED}  Installation completed with issues${NC}"
    echo -e "${RED}=====================================${NC}"
    echo ""
    echo "Some services failed to start. Please check:"
    echo "  sudo systemctl status wifi-portal"
    echo "  sudo systemctl status wifi-check"
    echo ""
    echo "View logs with:"
    echo "  sudo journalctl -u wifi-portal -n 50"
    echo "  sudo journalctl -u wifi-check -n 50"
fi
