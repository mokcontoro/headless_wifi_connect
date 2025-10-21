#!/bin/bash
# Comitup Installation Script for Raspberry Pi 5 Bookworm
# Replaces custom WiFi solution with production-grade Comitup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Comitup Installation${NC}"
echo -e "${BLUE}  Production-Grade WiFi Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Please run: sudo bash install_comitup.sh"
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

    if [ -n "$VERSION_ID" ] && [ "$VERSION_ID" -lt "12" ]; then
        echo -e "${RED}ERROR: This script requires Debian 12 (Bookworm) or newer${NC}"
        echo "Your version: $PRETTY_NAME"
        exit 1
    fi
fi

echo ""
echo -e "${YELLOW}This will install Comitup - a production-grade WiFi setup solution${NC}"
echo ""
echo "What is Comitup?"
echo "  - Mature, stable WiFi provisioning system"
echo "  - Captive portal for easy WiFi configuration"
echo "  - Automatic hotspot when no connection available"
echo "  - Remembers multiple networks"
echo "  - Used in production by many projects"
echo ""
read -p "Continue with installation? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo ""
echo -e "${BLUE}[1/7] Checking system requirements...${NC}"

# Check if NetworkManager is installed
if ! command -v nmcli &> /dev/null; then
    echo -e "${YELLOW}NetworkManager not found, installing...${NC}"
    apt-get update
    apt-get install -y network-manager
else
    echo "  ✓ NetworkManager found"
fi

# Ensure NetworkManager is enabled and running
systemctl enable NetworkManager
systemctl start NetworkManager
echo "  ✓ NetworkManager enabled"

echo ""
echo -e "${BLUE}[2/7] Adding Comitup repository...${NC}"

# Download and install Comitup apt source
echo "  Downloading Comitup repository package..."
wget -q https://davesteele.github.io/comitup/latest/davesteele-comitup-apt-source_latest.deb \
    -O /tmp/comitup-apt-source.deb

echo "  Installing repository package..."
dpkg -i --force-all /tmp/comitup-apt-source.deb
rm /tmp/comitup-apt-source.deb

echo "  ✓ Comitup repository added"

echo ""
echo -e "${BLUE}[3/7] Updating package lists...${NC}"
apt-get update

echo ""
echo -e "${BLUE}[4/7] Installing Comitup...${NC}"
apt-get install -y comitup

echo "  ✓ Comitup installed"

echo ""
echo -e "${BLUE}[5/7] Configuring Comitup...${NC}"

# Configure Comitup with custom SSID prefix
COMITUP_CONF="/etc/comitup.conf"

if [ -f "$COMITUP_CONF" ]; then
    echo "  Customizing Comitup configuration..."

    # Set AP name to wifi_connect_cam
    sed -i 's/^#*ap_name:.*/ap_name: wifi_connect_cam/' "$COMITUP_CONF"

    # Set AP password
    sed -i 's/^#*ap_password:.*/ap_password: smartcam/' "$COMITUP_CONF"

    # Enable web service
    sed -i 's/^#*web_service:.*/web_service: true/' "$COMITUP_CONF"

    echo "  ✓ Configuration updated:"
    echo "     AP Name: wifi_connect_cam-<device_id>"
    echo "     AP Password: smartcam"
    echo "     Web Portal: http://10.41.0.1"
else
    echo -e "  ${YELLOW}Warning: Config file not found at $COMITUP_CONF${NC}"
fi

echo ""
echo -e "${BLUE}[6/7] Enabling Comitup service...${NC}"

# Enable and start comitup
systemctl enable comitup
systemctl start comitup

# Wait for service to initialize
sleep 3

if systemctl is-active --quiet comitup; then
    echo "  ✓ Comitup service running"
else
    echo -e "  ${RED}✗ Comitup service failed to start${NC}"
    echo "  Check logs with: sudo journalctl -u comitup -n 50"
fi

echo ""
echo -e "${BLUE}[7/7] Cleaning up...${NC}"

# Remove old WiFi interface config if present
if [ -f /etc/network/interfaces ]; then
    # Backup original
    cp /etc/network/interfaces /etc/network/interfaces.backup

    # Remove wlan references
    sed -i '/wlan/d' /etc/network/interfaces
    echo "  ✓ Cleaned up interface configuration"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Comitup Configuration:${NC}"
echo "  AP Name:    wifi_connect_cam-<device_id>"
echo "  AP Password: smartcam"
echo "  Web Portal:  http://10.41.0.1"
echo ""
echo -e "${BLUE}How to Use:${NC}"
echo "  1. Reboot your Raspberry Pi: sudo reboot"
echo "  2. Wait 1-2 minutes after boot"
echo "  3. Look for 'wifi_connect_cam-XXXX' WiFi network"
echo "  4. Connect with password 'smartcam'"
echo "  5. Portal opens automatically at http://10.41.0.1"
echo "  6. Select your WiFi network and enter password"
echo "  7. Done! Pi will connect and remember the network"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "  Check status:    sudo systemctl status comitup"
echo "  View logs:       sudo journalctl -u comitup -f"
echo "  Restart:         sudo systemctl restart comitup"
echo "  Configuration:   sudo nano /etc/comitup.conf"
echo ""
echo -e "${YELLOW}Reboot recommended:${NC} sudo reboot"
echo ""
