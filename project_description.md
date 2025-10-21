# Headless WiFi Setup for Raspberry Pi Camera App

## Project Overview
This project provides a solution for distributing a camera application on Raspberry Pi 5 devices running Bookworm OS. The key requirement is enabling end-users to configure WiFi connectivity without requiring a keyboard, mouse, or screen (headless setup).

## Target Platform
- **Device**: Raspberry Pi 5
- **OS**: Raspberry Pi OS Bookworm (Debian 12)
- **Application**: Camera app
- **Network Manager**: NetworkManager (default in Bookworm)

## User Requirement
Users need to set up WiFi connectivity on their Raspberry Pi device without any physical peripherals (keyboard, mouse, monitor).

## Solution Approach: WiFi Access Point + Captive Portal

### How It Works
1. **First Boot**: Raspberry Pi creates its own WiFi network (e.g., "RaspiCam-Setup-XXXX")
2. **User Connects**: User connects to this network with their phone/tablet
3. **Captive Portal**: Web interface automatically opens (like hotel WiFi)
4. **Configuration**: User enters their home WiFi credentials via web form
5. **Saves & Connects**: Pi saves credentials using NetworkManager and connects to home network
6. **Normal Operation**: Camera app becomes accessible on home network

### Technology Stack
- **AP Mode**: NetworkManager hotspot (native to Bookworm)
- **Web Server**: Python Flask (lightweight, easy to deploy)
- **Captive Portal**: dnsmasq + iptables redirect
- **WiFi Configuration**: NetworkManager CLI (nmcli)
- **Auto-start**: systemd service
- **Frontend**: Pure HTML/CSS/JavaScript (no dependencies)

### Key Features
- No additional hardware required
- Works with any smartphone or tablet
- Automatic captive portal detection
- Secure credential handling
- Persistent configuration
- Support for hidden networks
- Network priority management
- Automatic fallback to AP mode if WiFi fails

### Bookworm Compatibility
- Uses NetworkManager (default in Bookworm, replaces dhcpcd)
- Compatible with Pi 5 hardware and drivers
- Systemd service management
- Python 3.11+ compatible
