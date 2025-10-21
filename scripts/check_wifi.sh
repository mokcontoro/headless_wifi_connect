#!/bin/bash
# WiFi Connection Checker Script
# Monitors WiFi connectivity and enables AP mode if connection is lost
# Designed for Raspberry Pi 5 Bookworm OS

set -euo pipefail

# Configuration
AP_CONNECTION_NAME="WiFi-Setup-AP"
SETUP_AP_SCRIPT="/usr/local/bin/setup_ap.sh"
LOG_TAG="wifi-checker"
CHECK_INTERVAL=60  # seconds between checks (increased for stability)
LOCK_FILE="/var/lock/wifi-checker.lock"
STATE_FILE="/var/run/wifi-checker.state"

# Function to acquire lock
acquire_lock() {
    local timeout=10
    local count=0
    while [ $count -lt $timeout ]; do
        if mkdir "$LOCK_FILE" 2>/dev/null; then
            trap 'release_lock' EXIT
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    return 1
}

# Function to release lock
release_lock() {
    rmdir "$LOCK_FILE" 2>/dev/null || true
}

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    logger -t "$LOG_TAG" "$1"
}

# Function to get current state
get_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "unknown"
    fi
}

# Function to set current state
set_state() {
    echo "$1" > "$STATE_FILE"
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
    # Acquire lock to prevent race conditions
    if ! acquire_lock; then
        log_message "Could not acquire lock, skipping this check"
        return
    fi

    local current_state=$(get_state)

    if is_ap_active; then
        # We're in AP mode - check if user has configured WiFi
        if [ "$current_state" != "ap_mode" ]; then
            set_state "ap_mode"
            log_message "Entered AP mode"
        fi

        if has_saved_networks; then
            log_message "Saved networks found while in AP mode"
            # Don't immediately try to switch - this causes instability
            # Wait for user to finish configuration
        fi
    else
        # We're not in AP mode - check if we're connected
        if is_wifi_connected; then
            # Successfully connected to WiFi
            if [ "$current_state" != "connected" ]; then
                set_state "connected"
                log_message "WiFi connected successfully"
            fi

            # Verify internet (but don't act on it immediately)
            if has_internet; then
                if [ "$current_state" != "connected_internet" ]; then
                    set_state "connected_internet"
                    log_message "WiFi connected with internet access"
                fi
            fi
        else
            # Not connected to WiFi
            if [ "$current_state" == "connected" ] || [ "$current_state" == "connected_internet" ]; then
                log_message "WiFi connection lost"
            fi

            if has_saved_networks; then
                # Give NetworkManager time to auto-reconnect
                log_message "No active WiFi connection, waiting for auto-reconnect..."
                set_state "reconnecting"
                release_lock
                sleep 45  # Longer wait for NetworkManager to try reconnecting

                # Reacquire lock after wait
                if ! acquire_lock; then
                    return
                fi

                # Check again after wait
                if ! is_wifi_connected; then
                    log_message "Auto-reconnect failed after wait, enabling AP mode"
                    set_state "switching_to_ap"
                    bash "$SETUP_AP_SCRIPT" 2>&1 | logger -t "$LOG_TAG"
                else
                    log_message "Auto-reconnect successful"
                    set_state "connected"
                fi
            else
                # No saved networks, enable AP immediately
                log_message "No saved networks found, enabling AP mode"
                set_state "switching_to_ap"
                bash "$SETUP_AP_SCRIPT" 2>&1 | logger -t "$LOG_TAG"
            fi
        fi
    fi

    release_lock
}

# Main execution
main() {
    log_message "WiFi checker started"

    # Clean up old lock if exists (in case of unclean shutdown)
    rmdir "$LOCK_FILE" 2>/dev/null || true

    # Initial wait after boot - give system time to stabilize
    log_message "Waiting for system to stabilize after boot..."
    sleep 30

    # Check if setup script exists
    if [ ! -f "$SETUP_AP_SCRIPT" ]; then
        log_message "ERROR: Setup AP script not found at $SETUP_AP_SCRIPT"
        exit 1
    fi

    # Initial state check
    if ! has_saved_networks && ! is_ap_active; then
        log_message "No saved networks and AP not active - enabling AP mode"
        if acquire_lock; then
            set_state "initial_setup"
            bash "$SETUP_AP_SCRIPT" 2>&1 | logger -t "$LOG_TAG"
            release_lock
        fi
    fi

    # Continuous monitoring loop with error handling
    while true; do
        if ! check_and_act; then
            log_message "Check cycle encountered an error, continuing..."
        fi
        sleep "$CHECK_INTERVAL"
    done
}

# Cleanup on exit
cleanup() {
    log_message "WiFi checker stopping"
    release_lock
    rm -f "$STATE_FILE"
}

trap cleanup EXIT INT TERM

# Run main function
main
