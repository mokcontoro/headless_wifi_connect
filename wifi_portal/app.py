#!/usr/bin/env python3
"""
WiFi Configuration Portal for Raspberry Pi 5 Bookworm
Flask web server providing captive portal for WiFi setup
"""

from flask import Flask, render_template, request, jsonify
import subprocess
import os
import sys
import json
import re

app = Flask(__name__)

# Path to the WiFi configuration script
SCRIPTS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'scripts')
CONFIGURE_WIFI_SCRIPT = os.path.join(SCRIPTS_DIR, 'configure_wifi.sh')
AP_CONNECTION_NAME = "WiFi-Setup-AP"


def run_command(cmd, timeout=30):
    """Run a shell command and return output"""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except Exception as e:
        return -1, "", str(e)


def get_available_networks():
    """Scan for available WiFi networks"""
    code, stdout, stderr = run_command("nmcli -t -f SSID,SIGNAL,SECURITY device wifi list")

    networks = []
    seen_ssids = set()

    if code == 0:
        for line in stdout.strip().split('\n'):
            if not line:
                continue
            parts = line.split(':')
            if len(parts) >= 2:
                ssid = parts[0]
                signal = parts[1] if len(parts) > 1 else "0"
                security = parts[2] if len(parts) > 2 else ""

                # Skip empty SSID and duplicates
                if ssid and ssid not in seen_ssids and ssid != "--":
                    networks.append({
                        'ssid': ssid,
                        'signal': signal,
                        'secured': bool(security and security != '--')
                    })
                    seen_ssids.add(ssid)

    # Sort by signal strength
    networks.sort(key=lambda x: int(x['signal']) if x['signal'].isdigit() else 0, reverse=True)
    return networks


def validate_ssid(ssid):
    """Validate WiFi SSID"""
    if not ssid or len(ssid) > 32:
        return False
    return True


def validate_password(password):
    """Validate WiFi password"""
    if not password:
        return False
    if len(password) < 8 or len(password) > 63:
        return False
    return True


@app.route('/')
def index():
    """Main configuration page"""
    return render_template('index.html')


@app.route('/scan')
def scan_networks():
    """API endpoint to scan for WiFi networks"""
    networks = get_available_networks()
    return jsonify({'networks': networks})


@app.route('/configure', methods=['POST'])
def configure_wifi():
    """API endpoint to configure WiFi"""
    try:
        data = request.get_json()
        ssid = data.get('ssid', '').strip()
        password = data.get('password', '')
        hidden = data.get('hidden', False)

        # Validate inputs
        if not validate_ssid(ssid):
            return jsonify({
                'success': False,
                'message': 'Invalid SSID. Must be 1-32 characters.'
            }), 400

        if not validate_password(password):
            return jsonify({
                'success': False,
                'message': 'Invalid password. Must be 8-63 characters.'
            }), 400

        # Build command
        cmd = f'bash "{CONFIGURE_WIFI_SCRIPT}" "{ssid}" "{password}" 200'
        if hidden:
            cmd += ' --hidden'

        # Execute configuration
        code, stdout, stderr = run_command(cmd, timeout=60)

        if code == 0:
            # Schedule AP shutdown and system operations
            # Give time for the response to be sent before disconnecting
            subprocess.Popen([
                'bash', '-c',
                'sleep 3 && nmcli connection down "{}" 2>/dev/null || true'.format(AP_CONNECTION_NAME)
            ])

            return jsonify({
                'success': True,
                'message': 'WiFi configured successfully! Connecting to network...'
            })
        else:
            error_msg = stderr if stderr else stdout
            return jsonify({
                'success': False,
                'message': f'Configuration failed: {error_msg}'
            }), 500

    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Error: {str(e)}'
        }), 500


@app.route('/status')
def status():
    """API endpoint to check current WiFi status"""
    # Check if connected to a WiFi network (not AP mode)
    code, stdout, _ = run_command(
        "nmcli -t -f TYPE,STATE connection show --active | grep '802-11-wireless:activated'"
    )

    if code == 0:
        # Get connection details
        code, stdout, _ = run_command(
            "nmcli -t -f NAME,IP4.ADDRESS connection show --active | grep '802-11-wireless'"
        )
        if code == 0:
            lines = stdout.strip().split('\n')
            if lines:
                parts = lines[0].split(':')
                return jsonify({
                    'connected': True,
                    'ssid': parts[0] if len(parts) > 0 else 'Unknown',
                    'ip': parts[1] if len(parts) > 1 else 'N/A'
                })

    return jsonify({
        'connected': False,
        'ssid': None,
        'ip': None
    })


@app.route('/generate_204')
@app.route('/hotspot-detect.html')
@app.route('/connecttest.txt')
@app.route('/redirect')
def captive_portal_redirect():
    """Handle captive portal detection from various devices"""
    return render_template('index.html')


if __name__ == '__main__':
    # Check if configuration script exists
    if not os.path.exists(CONFIGURE_WIFI_SCRIPT):
        print(f"ERROR: WiFi configuration script not found at {CONFIGURE_WIFI_SCRIPT}")
        sys.exit(1)

    # Run Flask server
    # Bind to all interfaces on port 80 (requires root)
    app.run(host='0.0.0.0', port=80, debug=False)
