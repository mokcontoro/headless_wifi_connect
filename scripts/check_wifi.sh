#!/bin/bash
# WiFi Connection Checker Script
# Monitors WiFi connectivity and enables AP mode if connection is lost
# Designed for Raspberry Pi 5 Bookworm OS

set -euo pipefail

# Configuration
AP_CONNECTION_NAME="WiFi-Setup-AP"
SETUP_AP_SCRIPT="/usr/local/bin/setup_ap.sh"
LOG_TAG="wifi-checker"
CHECK_INTERVAL=30  # seconds between checks

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    logger -t "$LOG_TAG" "$1"
}

# Check if we're connected to any WiFi network (excluding our AP)
is_wifi_connected() {
    # Get active WiFi connections excluding our AP
    local active_wifi
    active_wifi=$(nmcli -t -f NAME,TYPE connection show --active | \
                  grep '802-11-wireless' | \
                  grep -v "$AP_CONNECTION_NAME" || true)

    if [ -n "$active_wifi" ]; then
        return 0  # Connected
    else
        return 1  # Not connected
    fi
}

# Check if AP mode is currently active
is_ap_active() {
    nmcli -t -f NAME connection show --active | grep -Fxq "$AP_CONNECTION_NAME"
}

# Check if we have any saved WiFi profiles (excluding AP)
has_saved_networks() {
    local saved_networks
    saved_networks=$(nmcli -t -f NAME,TYPE connection show | \
                     grep '802-11-wireless' | \
                     grep -v "$AP_CONNECTION_NAME" || true)

    [ -n "$saved_networks" ]
}

# Check internet connectivity
has_internet() {
    # Try to reach common DNS servers
    ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1 || \
    ping -c 1 -W 2 1.1.1.1 > /dev/null 2>&1
}

# Main checking logic
check_and_act() {
    if is_ap_active; then
        # We're in AP mode - check if user has configured WiFi
        if has_saved_networks; then
            log_message "Saved networks found, attempting to connect..."
            # Disable AP and try to connect to saved networks
            nmcli connection down "$AP_CONNECTION_NAME" 2>/dev/null || true
            sleep 5

            # Wait for auto-connect
            local retries=6
            while [ $retries -gt 0 ]; do
                if is_wifi_connected && has_internet; then
                    log_message "Successfully connected to WiFi network"
                    return 0
                fi
                sleep 5
                ((retries--))
            done

            # Failed to connect, restart AP
            log_message "Failed to connect to saved networks, restarting AP mode"
            bash "$SETUP_AP_SCRIPT" 2>&1 | logger -t "$LOG_TAG"
        else
            log_message "AP mode active, waiting for user configuration"
        fi
    else
        # We're not in AP mode - check if we're connected
        if ! is_wifi_connected; then
            log_message "WiFi disconnected, checking for saved networks..."

            if has_saved_networks; then
                log_message "Waiting for auto-reconnect..."
                sleep 30

                # Check again after wait
                if ! is_wifi_connected; then
                    log_message "Auto-reconnect failed, enabling AP mode"
                    bash "$SETUP_AP_SCRIPT" 2>&1 | logger -t "$LOG_TAG"
                fi
            else
                log_message "No saved networks, enabling AP mode"
                bash "$SETUP_AP_SCRIPT" 2>&1 | logger -t "$LOG_TAG"
            fi
        else
            # Connected - verify internet access
            if has_internet; then
                log_message "WiFi connected with internet access"
            else
                log_message "WiFi connected but no internet access"
            fi
        fi
    fi
}

# Main execution
main() {
    log_message "WiFi checker started"

    # Initial check after boot
    sleep 10

    # Check if setup script exists
    if [ ! -f "$SETUP_AP_SCRIPT" ]; then
        log_message "ERROR: Setup AP script not found at $SETUP_AP_SCRIPT"
        exit 1
    fi

    # Initial state check
    if ! has_saved_networks && ! is_ap_active; then
        log_message "No saved networks and AP not active - enabling AP mode"
        bash "$SETUP_AP_SCRIPT" 2>&1 | logger -t "$LOG_TAG"
    fi

    # Continuous monitoring loop
    while true; do
        check_and_act
        sleep "$CHECK_INTERVAL"
    done
}

# Run main function
main
