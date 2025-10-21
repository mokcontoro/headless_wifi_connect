#!/bin/bash
# WiFi Access Point Setup Script for Raspberry Pi 5 Bookworm
# Creates a WiFi hotspot using NetworkManager

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AP_SSID_PREFIX="wifi_connect_cam"
AP_PASSWORD="smartcam"
AP_IP="192.168.4.1"
AP_CONNECTION_NAME="WiFi-Setup-AP"

echo -e "${BLUE}===== Raspberry Pi 5 WiFi AP Setup =====${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Please run: sudo $0"
    exit 1
fi

# Verify NetworkManager is installed (default in Bookworm)
if ! command -v nmcli &> /dev/null; then
    echo -e "${RED}ERROR: NetworkManager not found${NC}"
    echo "Install it with: sudo apt install network-manager"
    exit 1
fi

# Auto-detect WiFi interface
echo -e "${GREEN}Detecting WiFi interface...${NC}"
IFACE="$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1; exit}')"

if [ -z "$IFACE" ]; then
    echo -e "${RED}ERROR: No WiFi interface found${NC}"
    echo "Available interfaces:"
    nmcli device status
    exit 1
fi

echo -e "${GREEN}WiFi interface:${NC} $IFACE"

# Generate unique SSID using last 4 chars of MAC address
MAC_ADDR=$(cat /sys/class/net/"$IFACE"/address | tr -d ':')
DEVICE_ID="${MAC_ADDR: -4}"
DEVICE_ID="${DEVICE_ID^^}"  # Convert to uppercase
AP_SSID="${AP_SSID_PREFIX}-${DEVICE_ID}"

echo -e "${GREEN}AP SSID:${NC}        $AP_SSID"
echo -e "${GREEN}AP Password:${NC}    $AP_PASSWORD"
echo -e "${GREEN}AP IP:${NC}          $AP_IP"
echo ""

# Delete existing AP connection if present
if nmcli -t -f NAME connection show | grep -Fxq "$AP_CONNECTION_NAME"; then
    echo -e "${YELLOW}Removing existing AP connection...${NC}"
    nmcli connection delete "$AP_CONNECTION_NAME" 2>/dev/null || true
fi

# Create WiFi hotspot using NetworkManager
echo -e "${GREEN}Creating WiFi hotspot...${NC}"

nmcli connection add type wifi ifname "$IFACE" \
    con-name "$AP_CONNECTION_NAME" \
    autoconnect no \
    ssid "$AP_SSID"

# Configure as an Access Point
nmcli connection modify "$AP_CONNECTION_NAME" \
    802-11-wireless.mode ap \
    802-11-wireless.band bg \
    ipv4.method shared \
    ipv4.addresses "$AP_IP/24"

# Set WPA2-PSK security
nmcli connection modify "$AP_CONNECTION_NAME" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$AP_PASSWORD"

# Additional settings for stability on Pi 5
nmcli connection modify "$AP_CONNECTION_NAME" \
    802-11-wireless.powersave disable \
    connection.autoconnect-priority -100

echo -e "${GREEN}Activating access point...${NC}"

# Bring up the AP
if nmcli connection up "$AP_CONNECTION_NAME" 2>/dev/null; then
    echo ""
    echo -e "${GREEN}===== Access Point Active! =====${NC}"
    echo ""
    echo -e "${GREEN}SSID:${NC}      $AP_SSID"
    echo -e "${GREEN}Password:${NC}  $AP_PASSWORD"
    echo -e "${GREEN}Portal:${NC}    http://$AP_IP or http://setup.wifi"
    echo ""
    echo -e "${BLUE}Users can now connect and configure WiFi!${NC}"
    echo ""

    # Save SSID for other scripts to use
    echo "$AP_SSID" > /tmp/ap_ssid

    exit 0
else
    echo ""
    echo -e "${RED}===== Failed to activate AP =====${NC}"
    echo -e "${YELLOW}Troubleshooting steps:${NC}"
    echo "1. Check if WiFi is enabled: nmcli radio wifi on"
    echo "2. Disconnect from other networks: nmcli device disconnect $IFACE"
    echo "3. Check interface status: nmcli device status"
    echo "4. View detailed logs: journalctl -xe"
    exit 1
fi
