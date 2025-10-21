#!/bin/bash
# Uninstall Script for Headless WiFi Connect

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}  Headless WiFi Connect Uninstaller ${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Please run: sudo bash uninstall.sh"
    exit 1
fi

echo -e "${YELLOW}This will remove all headless WiFi connect components.${NC}"
echo -e "${YELLOW}Your WiFi configurations will be preserved.${NC}"
echo ""
read -p "Continue with uninstall? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""
echo -e "${GREEN}[1/5] Stopping services...${NC}"

systemctl stop wifi-portal.service 2>/dev/null || true
systemctl stop wifi-check.service 2>/dev/null || true

echo -e "${GREEN}[2/5] Disabling services...${NC}"

systemctl disable wifi-portal.service 2>/dev/null || true
systemctl disable wifi-check.service 2>/dev/null || true

echo -e "${GREEN}[3/5] Removing service files...${NC}"

rm -f /etc/systemd/system/wifi-portal.service
rm -f /etc/systemd/system/wifi-check.service

systemctl daemon-reload

echo -e "${GREEN}[4/5] Removing installed files...${NC}"

# Remove from bin directory
rm -f /usr/local/bin/setup_ap.sh
rm -f /usr/local/bin/check_wifi.sh
rm -f /usr/local/bin/configure_wifi.sh

# Remove installation directory
rm -rf /opt/headless_wifi_connect

# Remove dnsmasq captive portal config
rm -f /etc/dnsmasq.d/captive-portal.conf

# Restart dnsmasq if running
if systemctl is-active --quiet dnsmasq; then
    systemctl restart dnsmasq 2>/dev/null || true
fi

echo -e "${GREEN}[5/5] Cleaning up AP connection...${NC}"

# Remove AP connection profile
nmcli connection delete "WiFi-Setup-AP" 2>/dev/null || true

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  Uninstall Complete!               ${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${BLUE}Remaining WiFi configurations:${NC}"
nmcli connection show | grep wifi || echo "  None"
echo ""
echo -e "${YELLOW}Note: Your saved WiFi networks are still configured.${NC}"
echo -e "${YELLOW}To remove them, use: sudo nmcli connection delete <name>${NC}"
echo ""
