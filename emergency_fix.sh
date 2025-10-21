#!/bin/bash
# Emergency WiFi System Fix Script
# Fixes connection loops and misconfigurations

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}========================================${NC}"
echo -e "${RED}  WiFi Emergency Fix Script${NC}"
echo -e "${RED}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Please run: sudo bash emergency_fix.sh"
    exit 1
fi

# Configuration
AP_CONNECTION_NAME="WiFi-Setup-AP"

echo -e "${YELLOW}This script will:${NC}"
echo "  1. Stop the connection loop"
echo "  2. Fix AP connection settings"
echo "  3. Clean up state files"
echo "  4. Restart services properly"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${BLUE}[1/6] Stopping services...${NC}"
systemctl stop wifi-check 2>/dev/null && echo "  Stopped wifi-check" || echo "  wifi-check was not running"
sleep 2

echo ""
echo -e "${BLUE}[2/6] Cleaning up state files...${NC}"
if [ -f /var/run/wifi-checker.state ]; then
    rm -f /var/run/wifi-checker.state
    echo "  Removed state file"
else
    echo "  No state file to remove"
fi

if [ -d /var/lock/wifi-checker.lock ]; then
    rmdir /var/lock/wifi-checker.lock 2>/dev/null && echo "  Removed lock file" || echo "  Lock file already removed"
else
    echo "  No lock file to remove"
fi

echo ""
echo -e "${BLUE}[3/6] Fixing AP connection settings...${NC}"

# Check if AP connection exists
if nmcli -t -f NAME connection show | grep -Fxq "$AP_CONNECTION_NAME"; then
    echo "  AP connection found, updating settings..."

    # Disable autoconnect
    nmcli connection modify "$AP_CONNECTION_NAME" connection.autoconnect no
    echo "  ✓ Set autoconnect to 'no'"

    # Set very low priority
    nmcli connection modify "$AP_CONNECTION_NAME" connection.autoconnect-priority -999
    echo "  ✓ Set priority to -999 (lowest)"

    # Disable autoconnect slaves
    nmcli connection modify "$AP_CONNECTION_NAME" connection.autoconnect-slaves no
    echo "  ✓ Disabled autoconnect-slaves"

    # Verify settings
    AUTOCONNECT=$(nmcli -t -f connection.autoconnect connection show "$AP_CONNECTION_NAME" | cut -d: -f2)
    if [ "$AUTOCONNECT" = "no" ]; then
        echo -e "  ${GREEN}✓ AP connection configured correctly${NC}"
    else
        echo -e "  ${RED}✗ Failed to set autoconnect${NC}"
    fi
else
    echo "  AP connection not found (will be created when needed)"
fi

echo ""
echo -e "${BLUE}[4/6] Checking for problematic connections...${NC}"

# Check if any non-AP WiFi connections exist
WIFI_COUNT=$(nmcli -t -f NAME,TYPE connection show | \
             grep '802-11-wireless' | \
             grep -v "$AP_CONNECTION_NAME" | \
             wc -l)

echo "  Found $WIFI_COUNT saved WiFi network(s)"

if [ "$WIFI_COUNT" -eq 0 ]; then
    echo -e "  ${YELLOW}No WiFi networks configured - AP mode will be activated${NC}"
    SHOULD_START_AP=true
else
    echo "  Saved networks detected - will try to connect"
    SHOULD_START_AP=false

    # List the networks
    echo "  Networks:"
    nmcli -t -f NAME,TYPE connection show | \
    grep '802-11-wireless' | \
    grep -v "$AP_CONNECTION_NAME" | \
    cut -d: -f1 | \
    while read -r network; do
        echo "    - $network"
    done
fi

echo ""
echo -e "${BLUE}[5/6] Resetting WiFi interface...${NC}"

# Get WiFi interface
WIFI_IFACE=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1; exit}')

if [ -n "$WIFI_IFACE" ]; then
    echo "  WiFi interface: $WIFI_IFACE"

    # Disconnect everything
    echo "  Disconnecting all connections..."
    nmcli device disconnect "$WIFI_IFACE" 2>/dev/null || true
    sleep 2

    # Turn WiFi off and on
    echo "  Resetting WiFi radio..."
    nmcli radio wifi off
    sleep 1
    nmcli radio wifi on
    sleep 2

    # Set to managed
    nmcli device set "$WIFI_IFACE" managed yes
    echo "  ✓ WiFi interface reset"
else
    echo -e "  ${RED}✗ No WiFi interface found${NC}"
fi

echo ""
echo -e "${BLUE}[6/6] Restarting services...${NC}"

# Start portal
systemctl start wifi-portal
sleep 2

if systemctl is-active --quiet wifi-portal; then
    echo "  ✓ WiFi portal started"
else
    echo -e "  ${RED}✗ WiFi portal failed to start${NC}"
fi

# Start or setup based on saved networks
if [ "$SHOULD_START_AP" = true ]; then
    echo "  Starting AP mode..."
    /usr/local/bin/setup_ap.sh
    sleep 3
else
    echo "  Waiting for network connection (10 seconds)..."
    sleep 10

    # Check if connected
    if nmcli -t -f NAME,TYPE connection show --active | grep -q '802-11-wireless'; then
        ACTIVE=$(nmcli -t -f NAME,TYPE connection show --active | grep '802-11-wireless' | cut -d: -f1)
        echo -e "  ${GREEN}✓ Connected to: $ACTIVE${NC}"
    else
        echo -e "  ${YELLOW}No connection established, starting AP mode...${NC}"
        /usr/local/bin/setup_ap.sh
        sleep 3
    fi
fi

# Start wifi-check with increased delay
echo "  Starting WiFi monitor (with 60s delay)..."
systemctl start wifi-check

if systemctl is-active --quiet wifi-check; then
    echo "  ✓ WiFi monitor started"
else
    echo -e "  ${RED}✗ WiFi monitor failed to start${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Emergency Fix Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Show current status
echo "Current status:"
echo ""

if nmcli -t -f NAME,TYPE connection show --active | grep -q "$AP_CONNECTION_NAME"; then
    echo -e "  Mode: ${BLUE}AP Mode (Setup)${NC}"
    AP_SSID=$(nmcli -t -f 802-11-wireless.ssid connection show "$AP_CONNECTION_NAME" | cut -d: -f2)
    echo "  Network: $AP_SSID"
    echo "  Password: smartcam"
    echo "  Portal: http://192.168.4.1"
elif nmcli -t -f NAME,TYPE connection show --active | grep -q '802-11-wireless'; then
    ACTIVE=$(nmcli -t -f NAME,TYPE connection show --active | grep '802-11-wireless' | cut -d: -f1)
    echo -e "  Mode: ${GREEN}WiFi Connected${NC}"
    echo "  Network: $ACTIVE"
    IP=$(hostname -I | awk '{print $1}')
    echo "  IP: $IP"
else
    echo -e "  Mode: ${YELLOW}Disconnected${NC}"
    echo "  Waiting for connection..."
fi

echo ""
echo "Next steps:"
echo "  - Monitor logs: sudo journalctl -u wifi-check -f"
echo "  - Check status: nmcli device status"
echo "  - Run diagnostic: sudo bash diagnose_wifi.sh"
echo ""
echo "If problems persist, check /var/log/wifi-config.log for details"
echo ""
