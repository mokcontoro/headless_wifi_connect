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
LOOP_DETECT_FILE="/var/run/wifi-checker-loops.log"
MAX_LOOPS=3  # Max state changes in detection window
LOOP_WINDOW=300  # 5 minutes in seconds

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

# Record state transition for loop detection
record_transition() {
    local transition="$1"
    local timestamp=$(date +%s)
    echo "$timestamp $transition" >> "$LOOP_DETECT_FILE"

    # Clean old entries (older than LOOP_WINDOW)
    if [ -f "$LOOP_DETECT_FILE" ]; then
        local cutoff=$((timestamp - LOOP_WINDOW))
        grep -v "^[0-9]*" "$LOOP_DETECT_FILE" > "${LOOP_DETECT_FILE}.tmp" 2>/dev/null || true
        awk -v cutoff="$cutoff" '$1 >= cutoff' "$LOOP_DETECT_FILE" >> "${LOOP_DETECT_FILE}.tmp" 2>/dev/null || true
        mv "${LOOP_DETECT_FILE}.tmp" "$LOOP_DETECT_FILE"
    fi
}

# Check if we're in a connection loop
is_looping() {
    if [ ! -f "$LOOP_DETECT_FILE" ]; then
        return 1
    fi

    # Count transitions in the last LOOP_WINDOW seconds
    local count=$(wc -l < "$LOOP_DETECT_FILE" 2>/dev/null || echo "0")

    if [ "$count" -ge "$MAX_LOOPS" ]; then
        return 0  # Yes, we're looping
    else
        return 1  # No loop detected
    fi
}

# Enter emergency mode (stop making changes)
enter_emergency_mode() {
    log_message "EMERGENCY: Connection loop detected! Entering safe mode"
    log_message "Stopping automatic network switching for 10 minutes"

    # Set a flag to prevent further actions
    echo "emergency" > "$STATE_FILE"
    echo "$(date +%s)" > "${STATE_FILE}.emergency_until"

    # Clear loop log
    rm -f "$LOOP_DETECT_FILE"

    # Make sure AP is active so user can reconfigure
    if ! is_ap_active; then
        log_message "Activating AP mode for recovery"
        bash "$SETUP_AP_SCRIPT" 2>&1 | logger -t "$LOG_TAG"
    fi
}

# Check if we're in emergency mode
is_emergency_mode() {
    if [ -f "${STATE_FILE}.emergency_until" ]; then
        local emergency_until=$(cat "${STATE_FILE}.emergency_until")
        local now=$(date +%s)
        local remaining=$((emergency_until + 600 - now))  # 10 minutes = 600 seconds

        if [ "$remaining" -gt 0 ]; then
            return 0  # Still in emergency mode
        else
            # Emergency period expired
            rm -f "${STATE_FILE}.emergency_until"
            log_message "Emergency mode expired, resuming normal operation"
            return 1
        fi
    fi
    return 1
}

# Main checking logic
check_and_act() {
    # Check if we're in emergency mode
    if is_emergency_mode; then
        log_message "In emergency mode, skipping checks"
        return
    fi

    # Acquire lock to prevent race conditions
    if ! acquire_lock; then
        log_message "Could not acquire lock, skipping this check"
        return
    fi

    # Check for connection loops
    if is_looping; then
        enter_emergency_mode
        release_lock
        return
    fi

    local current_state=$(get_state)

    if is_ap_active; then
        # We're in AP mode - check if user has configured WiFi
        if [ "$current_state" != "ap_mode" ]; then
            set_state "ap_mode"
            record_transition "enter_ap_mode"
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
            if [ "$current_state" != "connected" ] && [ "$current_state" != "connected_internet" ]; then
                set_state "connected"
                record_transition "wifi_connected"
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
                record_transition "wifi_disconnected"
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
                    record_transition "switch_to_ap"

                    # Final loop check before switching
                    if is_looping; then
                        log_message "Loop detected before AP activation, entering emergency mode"
                        enter_emergency_mode
                        release_lock
                        return
                    fi

                    bash "$SETUP_AP_SCRIPT" 2>&1 | logger -t "$LOG_TAG"
                else
                    log_message "Auto-reconnect successful"
                    set_state "connected"
                fi
            else
                # No saved networks, enable AP immediately
                log_message "No saved networks found, enabling AP mode"
                set_state "switching_to_ap"
                record_transition "switch_to_ap"
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
    rm -f "$LOOP_DETECT_FILE"
    rm -f "${STATE_FILE}.emergency_until"
}

trap cleanup EXIT INT TERM

# Run main function
main
