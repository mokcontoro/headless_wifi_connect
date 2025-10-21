# Raspberry Pi 5 Bookworm Setup Guide

This guide will walk you through setting up headless WiFi configuration on your Raspberry Pi 5 running Bookworm OS.

## Prerequisites

- Raspberry Pi 5
- MicroSD card (16GB+ recommended)
- Raspberry Pi OS Bookworm (64-bit recommended)
- Computer with SD card reader (for initial setup)
- WiFi network to connect to

## Step 1: Prepare the Raspberry Pi OS

### Download and Flash OS

1. Download [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Insert your microSD card
3. Open Raspberry Pi Imager
4. Choose **Raspberry Pi 5** as the device
5. Choose **Raspberry Pi OS (64-bit)** - Bookworm
6. Choose your SD card
7. Click the gear icon (⚙️) for advanced options:
   - Set hostname (e.g., `raspicam`)
   - **DO NOT** configure WiFi yet (this system will handle it)
   - Enable SSH with password authentication
   - Set username and password (e.g., user: `pi`, password: your choice)
   - Set locale settings
8. Click **Write** and wait for completion

## Step 2: Install Headless WiFi Connect

### Option A: Install from SD Card (Before First Boot)

1. After flashing, the SD card will have a `boot` partition
2. Copy the entire `headless_wifi_connect` folder to a USB drive
3. Insert SD card into Pi 5 and boot it up
4. Connect via Ethernet or use a keyboard/monitor for first-time setup
5. Copy the folder from USB to Pi:
   ```bash
   cp -r /media/usb/headless_wifi_connect /home/pi/
   ```
6. Run installation:
   ```bash
   cd /home/pi/headless_wifi_connect
   sudo bash install.sh
   ```

### Option B: Install from GitHub (Requires Internet)

If your Pi has Ethernet connection:

```bash
# SSH into your Pi (use Ethernet or monitor/keyboard)
ssh pi@raspicam.local

# Clone the repository
git clone https://github.com/mokcontoro/headless_wifi_connect.git
cd headless_wifi_connect

# Run installation
sudo bash install.sh
```

## Step 3: First Boot Configuration

After installation completes:

1. **Reboot** the Raspberry Pi:
   ```bash
   sudo reboot
   ```

2. **Wait 30-60 seconds** for the system to boot and create the hotspot

3. **Look for the WiFi network** on your phone/laptop:
   - Network name: `RaspiCam-Setup-XXXX` (XXXX = last 4 chars of MAC address)
   - Password: `raspberrypi`

4. **Connect** to this network

5. **Configure WiFi**:
   - Captive portal should open automatically
   - If not, open browser and go to: `http://192.168.4.1`
   - Select your WiFi network from the list
   - Enter the password
   - Click "Connect to Network"

6. **Done!** The Pi will:
   - Save your WiFi credentials
   - Connect to your network
   - Shut down the hotspot
   - Be accessible on your network

## Step 4: Verify Installation

After the Pi connects to your WiFi:

1. Find the Pi's IP address:
   ```bash
   # On the Pi (if you have access)
   hostname -I

   # Or scan your network
   # On Linux/Mac:
   arp -a | grep raspberrypi

   # Or use your router's admin interface
   ```

2. SSH into the Pi:
   ```bash
   ssh pi@raspicam.local
   # or
   ssh pi@<IP_ADDRESS>
   ```

3. Check service status:
   ```bash
   sudo systemctl status wifi-portal
   sudo systemctl status wifi-check
   ```

## Distributing to End Users

### Pre-configured SD Card Method

1. **Prepare a Master Image:**
   - Set up one Pi completely with your camera app
   - Install headless WiFi connect
   - Test thoroughly
   - Create an image of the SD card using Raspberry Pi Imager or `dd`

2. **Flash to Multiple Cards:**
   - Use the master image to flash multiple SD cards
   - Each Pi will have unique AP network name (based on MAC address)

3. **User Instructions Card:**
   Include a simple instruction card with each device:
   ```
   📷 RaspiCam Setup

   1. Power on the device
   2. Wait 1 minute
   3. Connect to WiFi: "RaspiCam-Setup-XXXX"
      Password: raspberrypi
   4. Follow on-screen instructions
   5. Done! Your camera is ready.

   Support: support@yourcompany.com
   ```

### Package Contents

Each package should include:
- Raspberry Pi 5 with pre-configured SD card
- Power supply (USB-C, 5V/5A recommended)
- Quick start guide card
- Camera module (if applicable)

## Troubleshooting

### Hotspot Doesn't Appear

```bash
# Check if services are running
sudo systemctl status wifi-portal
sudo systemctl status wifi-check

# Manually create hotspot
sudo setup_ap.sh

# Check WiFi interface
nmcli device status
```

### Can't Connect to Hotspot

```bash
# Check NetworkManager status
sudo systemctl status NetworkManager

# Restart services
sudo systemctl restart wifi-portal wifi-check

# Check for conflicts
sudo systemctl status wpa_supplicant
# If running, disable it:
sudo systemctl stop wpa_supplicant
sudo systemctl disable wpa_supplicant
```

### Portal Page Doesn't Load

```bash
# Check if Flask is running
sudo netstat -tulpn | grep :80

# View portal logs
sudo journalctl -u wifi-portal -f

# Test portal manually
curl http://192.168.4.1
```

### WiFi Won't Connect

```bash
# List saved networks
sudo configure_wifi.sh --list

# Try connecting manually
sudo nmcli device wifi connect "YourSSID" password "YourPassword"

# Check for errors
sudo journalctl -u NetworkManager -f
```

### Reset to Factory Settings

To clear all WiFi configurations and restart setup:

```bash
# Delete all WiFi connections
sudo nmcli connection delete $(nmcli -t -f NAME,TYPE connection show | grep 802-11-wireless | cut -d: -f1)

# Restart services
sudo systemctl restart wifi-check wifi-portal

# The hotspot should appear within 30 seconds
```

## Customization

### Change Hotspot Name

Edit `/usr/local/bin/setup_ap.sh`:
```bash
AP_SSID_PREFIX="YourBrand-Setup"
```

### Change Hotspot Password

Edit `/usr/local/bin/setup_ap.sh`:
```bash
AP_PASSWORD="your_secure_password"
```

### Change Portal Appearance

Edit `/opt/headless_wifi_connect/wifi_portal/templates/index.html`

### Auto-start Your Camera App

Create a systemd service for your camera app that starts after network is available:

```ini
[Unit]
Description=Camera Application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
ExecStart=/path/to/your/camera/app
Restart=always

[Install]
WantedBy=multi-user.target
```

## Advanced Configuration

### Static IP Assignment

To assign a static IP when connected to specific network:

```bash
sudo nmcli connection modify "YourSSID" \
  ipv4.method manual \
  ipv4.addresses 192.168.1.100/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns "8.8.8.8,8.8.4.4"
```

### Priority Networks

Set higher priority for preferred networks:

```bash
sudo configure_wifi.sh "HomeNetwork" "password123" 250
sudo configure_wifi.sh "MobileHotspot" "password456" 50
```

### Disable Auto-AP Mode

If you want to disable automatic AP fallback:

```bash
sudo systemctl stop wifi-check
sudo systemctl disable wifi-check
```

## Security Considerations

1. **Change Default Password**: Update the AP password in `setup_ap.sh`
2. **HTTPS**: For production, consider adding HTTPS to the portal
3. **Firewall**: Configure iptables to restrict access when in AP mode
4. **SSH Keys**: Use SSH keys instead of passwords for remote access
5. **Update Regularly**: Keep system and packages updated

```bash
sudo apt update && sudo apt upgrade -y
```

## Support

For issues, questions, or contributions:
- GitHub Issues: https://github.com/mokcontoro/headless_wifi_connect/issues
- Documentation: https://github.com/mokcontoro/headless_wifi_connect

## License

MIT License - See LICENSE file for details
