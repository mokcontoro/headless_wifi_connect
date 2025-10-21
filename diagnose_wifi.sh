#!/bin/bash
# WiFi System Diagnostic Script
# Diagnoses connection loop and configuration issues

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  WiFi System Diagnostic Tool${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Note: Some checks require root access${NC}"
    echo -e "${YELLOW}Run with: sudo bash diagnose_wifi.sh${NC}"
    echo ""
fi

# Configuration
AP_CONNECTION_NAME="WiFi-Setup-AP"
ISSUES_FOUND=0

# Function to print section header
print_section() {
    echo ""
    echo -e "${CYAN}=== $1 ===${NC}"
    echo ""
}

# Function to report issue
report_issue() {
    echo -e "${RED}[ISSUE] $1${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
}

# Function to report warning
report_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Function to report ok
report_ok() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_section "System Information"
echo "Hostname: $(hostname)"
echo "Date/Time: $(date)"
echo "Uptime: $(uptime -p)"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "OS: $PRETTY_NAME"
fi
echo "Kernel: $(uname -r)"

print_section "Service Status"

# Check wifi-portal service
if systemctl is-active --quiet wifi-portal; then
    report_ok "wifi-portal.service is running"
else
    report_issue "wifi-portal.service is NOT running"
    echo "  Start with: sudo systemctl start wifi-portal"
fi

# Check wifi-check service
if systemctl is-active --quiet wifi-check; then
    report_ok "wifi-check.service is running"

    # Check if it's restarting frequently
    RESTARTS=$(systemctl show wifi-check -p NRestarts --value)
    if [ "$RESTARTS" -gt 5 ]; then
        report_warning "wifi-check has restarted $RESTARTS times (possible crash loop)"
    fi
else
    report_warning "wifi-check.service is NOT running"
fi

# Check NetworkManager
if systemctl is-active --quiet NetworkManager; then
    report_ok "NetworkManager is running"
else
    report_issue "NetworkManager is NOT running"
fi

print_section "WiFi Interface Status"
nmcli device status
echo ""

WIFI_IFACE=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1; exit}')
if [ -n "$WIFI_IFACE" ]; then
    report_ok "WiFi interface found: $WIFI_IFACE"

    # Check if interface is managed
    if nmcli device show "$WIFI_IFACE" | grep -q "STATE.*connected"; then
        echo "  State: Connected"
    elif nmcli device show "$WIFI_IFACE" | grep -q "STATE.*disconnected"; then
        echo "  State: Disconnected"
    elif nmcli device show "$WIFI_IFACE" | grep -q "STATE.*connecting"; then
        report_warning "State: Connecting (may be stuck)"
    fi
else
    report_issue "No WiFi interface found"
fi

print_section "Active Connections"
ACTIVE_CONN=$(nmcli -t -f NAME,TYPE connection show --active)
if [ -n "$ACTIVE_CONN" ]; then
    echo "$ACTIVE_CONN" | while IFS=: read -r name type; do
        if [ "$type" = "802-11-wireless" ]; then
            if [ "$name" = "$AP_CONNECTION_NAME" ]; then
                echo -e "  ${GREEN}[AP MODE]${NC} $name"
            else
                echo -e "  ${GREEN}[WiFi]${NC} $name"
            fi
        fi
    done
else
    echo "  No active connections"
fi

print_section "Saved WiFi Connections"
echo "Checking all saved WiFi profiles..."
echo ""

nmcli -t -f NAME,TYPE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show | \
grep '802-11-wireless' | \
while IFS=: read -r name type autoconn priority; do
    if [ "$name" = "$AP_CONNECTION_NAME" ]; then
        echo -e "${BLUE}[AP Connection]${NC} $name"
    else
        echo -e "${GREEN}[WiFi Network]${NC} $name"
    fi

    echo "  Auto-connect: $autoconn"
    echo "  Priority: ${priority:-0}"

    # Check if AP has autoconnect enabled (BAD!)
    if [ "$name" = "$AP_CONNECTION_NAME" ] && [ "$autoconn" = "yes" ]; then
        report_issue "AP connection has autoconnect ENABLED - this causes loops!"
        echo "  Fix with: sudo nmcli connection modify '$AP_CONNECTION_NAME' connection.autoconnect no"
    fi

    echo ""
done

# Count non-AP WiFi networks
WIFI_COUNT=$(nmcli -t -f NAME,TYPE connection show | \
             grep '802-11-wireless' | \
             grep -v "$AP_CONNECTION_NAME" | \
             wc -l)

echo "Total saved WiFi networks (excluding AP): $WIFI_COUNT"

if [ "$WIFI_COUNT" -eq 0 ]; then
    report_warning "No WiFi networks configured - AP should be active"
fi

print_section "Connection Loop Detection"

# Check recent connection changes
echo "Checking for rapid connection/disconnection patterns..."
echo ""

# Check NetworkManager logs for connection patterns
if [ -f /var/log/syslog ]; then
    LOGFILE="/var/log/syslog"
elif [ -f /var/log/messages ]; then
    LOGFILE="/var/log/messages"
else
    LOGFILE=""
fi

if [ -n "$LOGFILE" ]; then
    # Look for connection state changes in last 10 minutes
    RECENT_CHANGES=$(grep -c "state change" "$LOGFILE" 2>/dev/null | tail -100 || echo "0")

    if [ "$RECENT_CHANGES" -gt 30 ]; then
        report_issue "Detected $RECENT_CHANGES state changes recently - possible connection loop!"
    elif [ "$RECENT_CHANGES" -gt 10 ]; then
        report_warning "Detected $RECENT_CHANGES state changes - monitoring recommended"
    else
        report_ok "Connection state appears stable"
    fi
fi

# Check for AP connection/disconnection loop
AP_ACTIVATIONS=$(journalctl -u wifi-check --since "10 minutes ago" 2>/dev/null | \
                 grep -c "enabling AP mode" || echo "0")

if [ "$AP_ACTIVATIONS" -gt 5 ]; then
    report_issue "AP mode activated $AP_ACTIVATIONS times in 10 minutes - LOOP DETECTED!"
    echo "  This indicates the wifi-check service is rapidly switching modes"
fi

print_section "State Files and Locks"

# Check state file
if [ -f /var/run/wifi-checker.state ]; then
    STATE=$(cat /var/run/wifi-checker.state)
    echo "Current state: $STATE"

    if [ "$STATE" = "switching_to_ap" ] || [ "$STATE" = "reconnecting" ]; then
        report_warning "State is '$STATE' - check if it's stuck in transition"
    fi
else
    echo "No state file found (may be normal if service just started)"
fi

# Check lock file
if [ -d /var/lock/wifi-checker.lock ]; then
    report_warning "Lock file exists - service may be running or stuck"
    echo "  If service is not running, remove with: sudo rmdir /var/lock/wifi-checker.lock"
else
    report_ok "No lock file (normal)"
fi

print_section "Recent Service Logs"

echo -e "${CYAN}wifi-check logs (last 30 lines):${NC}"
journalctl -u wifi-check -n 30 --no-pager 2>/dev/null || echo "Cannot access logs (need root)"

echo ""
echo -e "${CYAN}NetworkManager logs (last 20 lines):${NC}"
journalctl -u NetworkManager -n 20 --no-pager 2>/dev/null || echo "Cannot access logs (need root)"

print_section "Configuration Files Check"

# Check if scripts exist
if [ -f /usr/local/bin/setup_ap.sh ]; then
    report_ok "setup_ap.sh found"
else
    report_issue "setup_ap.sh NOT found at /usr/local/bin/"
fi

if [ -f /usr/local/bin/check_wifi.sh ]; then
    report_ok "check_wifi.sh found"
else
    report_issue "check_wifi.sh NOT found at /usr/local/bin/"
fi

if [ -f /usr/local/bin/configure_wifi.sh ]; then
    report_ok "configure_wifi.sh found"
else
    report_issue "configure_wifi.sh NOT found at /usr/local/bin/"
fi

# Check if portal exists
if [ -f /opt/headless_wifi_connect/wifi_portal/app.py ]; then
    report_ok "WiFi portal app found"
else
    report_issue "WiFi portal app NOT found"
fi

# Check configuration log
if [ -f /var/log/wifi-config.log ]; then
    echo ""
    echo -e "${CYAN}Recent WiFi configuration attempts:${NC}"
    tail -20 /var/log/wifi-config.log 2>/dev/null || echo "Cannot read log"
fi

print_section "Summary and Recommendations"

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}No critical issues detected!${NC}"
    echo ""
    echo "Your system appears to be configured correctly."
    echo "If you're experiencing issues, try:"
    echo "  1. Check if your WiFi network is in range"
    echo "  2. Verify your WiFi password is correct"
    echo "  3. Restart the services: sudo systemctl restart wifi-check wifi-portal"
else
    echo -e "${RED}Found $ISSUES_FOUND critical issue(s)${NC}"
    echo ""
    echo "Recommended actions:"
    echo ""

    # Specific recommendations based on findings
    if nmcli connection show "$AP_CONNECTION_NAME" 2>/dev/null | grep -q "connection.autoconnect.*yes"; then
        echo "1. Fix AP autoconnect:"
        echo "   sudo nmcli connection modify '$AP_CONNECTION_NAME' connection.autoconnect no"
        echo ""
    fi

    if [ "$AP_ACTIVATIONS" -gt 5 ]; then
        echo "2. Stop the connection loop:"
        echo "   sudo systemctl stop wifi-check"
        echo "   sudo rm -f /var/run/wifi-checker.state"
        echo "   sudo rmdir /var/lock/wifi-checker.lock 2>/dev/null || true"
        echo ""
    fi

    if [ "$WIFI_COUNT" -eq 0 ]; then
        echo "3. Configure WiFi network:"
        echo "   - Connect to wifi_connect_cam-XXXX network"
        echo "   - Open http://192.168.4.1 in browser"
        echo "   - Enter your WiFi credentials"
        echo ""
    fi

    echo "Or run the emergency fix script:"
    echo "   sudo bash emergency_fix.sh"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Diagnostic Complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "To save this report: sudo bash diagnose_wifi.sh > wifi_diagnostic_report.txt"
echo ""
