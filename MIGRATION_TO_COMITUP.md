# Migration Guide: Switching to Comitup

This guide explains how to migrate from the custom WiFi solution to **Comitup**, a production-grade, battle-tested WiFi provisioning system.

## Why Switch to Comitup?

### Problems with Custom Solution
- ❌ Connection loops and stability issues
- ❌ Race conditions between services
- ❌ Complex debugging required
- ❌ Custom code maintenance burden

### Benefits of Comitup
- ✅ **Production-ready** - Used in thousands of devices
- ✅ **Actively maintained** - Regular updates and bug fixes
- ✅ **Stable** - Years of testing and refinement
- ✅ **Simple** - Native Debian package, easy installation
- ✅ **Feature-rich** - Remembers multiple networks, dual WiFi support
- ✅ **Community support** - Active user base and documentation

## Migration Steps

### Step 1: Backup Current Configuration

```bash
# Save existing WiFi connections
nmcli connection show | grep wifi > ~/wifi_backup.txt

# Backup configuration (if needed)
cp -r /opt/headless_wifi_connect ~/headless_wifi_connect_backup
```

### Step 2: Uninstall Custom Solution

```bash
cd headless_wifi_connect
sudo bash uninstall.sh
```

This will:
- Stop and disable custom services
- Remove scripts and files
- Clean up state files
- **Preserve** your saved WiFi networks

### Step 3: Install Comitup

```bash
# Run the Comitup installation script
sudo bash install_comitup.sh
```

This will:
- Add Comitup repository
- Install Comitup with dependencies
- Configure custom AP name (wifi_connect_cam)
- Set AP password (smartcam)
- Enable and start Comitup service

### Step 4: Reboot

```bash
sudo reboot
```

### Step 5: Test

After reboot:

1. **Wait 1-2 minutes** for system to initialize
2. **Look for WiFi network**: `wifi_connect_cam-XXXX`
3. **Connect** with password: `smartcam`
4. **Portal opens** at: `http://10.41.0.1`
5. **Configure WiFi** through the web interface
6. **Done!** Pi connects to your network

## Comparison

### Custom Solution
```
- AP Name: wifi_connect_cam-XXXX
- Password: smartcam
- Portal: http://192.168.4.1
- Services: wifi-portal, wifi-check
```

### Comitup
```
- AP Name: wifi_connect_cam-XXXX  (same!)
- Password: smartcam              (same!)
- Portal: http://10.41.0.1       (different IP)
- Service: comitup                (single service)
```

## User Experience Changes

### Before (Custom Solution)
1. Connect to `wifi_connect_cam-XXXX`
2. Portal at `http://192.168.4.1`
3. Select network, enter password
4. Background process attempts connection
5. Wait ~35 seconds
6. AP disappears if successful

### After (Comitup)
1. Connect to `wifi_connect_cam-XXXX`
2. Portal at `http://10.41.0.1`
3. Select network, enter password
4. Connection attempt happens immediately
5. Feedback shown in real-time
6. AP disappears when connected

## Configuration

### Custom Settings

Edit `/etc/comitup.conf`:

```bash
sudo nano /etc/comitup.conf
```

Key settings:
```ini
# AP name prefix (device ID appended)
ap_name: wifi_connect_cam

# AP password
ap_password: smartcam

# Web service (captive portal)
web_service: true

# Base IP for AP
base_addr: 10.41.0

# External callback on state changes
external_callback: /usr/local/bin/comitup-callback
```

After changes:
```bash
sudo systemctl restart comitup
```

### Advanced: Custom Callback

Create `/usr/local/bin/comitup-callback` to run actions on state changes:

```bash
#!/bin/bash
# Called by Comitup on state changes
# Args: $1 = state, $2 = connection name

STATE=$1
CONNECTION=$2

case "$STATE" in
    HOTSPOT)
        # Entered hotspot mode
        logger "Comitup: Entered hotspot mode"
        ;;
    CONNECTING)
        # Attempting to connect
        logger "Comitup: Connecting to $CONNECTION"
        ;;
    CONNECTED)
        # Successfully connected
        logger "Comitup: Connected to $CONNECTION"
        # Start your camera app here if needed
        ;;
esac
```

Make it executable:
```bash
sudo chmod +x /usr/local/bin/comitup-callback
```

## Troubleshooting

### Comitup service not starting

```bash
# Check logs
sudo journalctl -u comitup -n 50

# Check status
sudo systemctl status comitup

# Restart
sudo systemctl restart comitup
```

### AP not appearing

```bash
# Check if NetworkManager is managing WiFi
nmcli device status

# Make sure wlan0 is not in /etc/network/interfaces
sudo nano /etc/network/interfaces
# Remove any wlan references

# Restart NetworkManager
sudo systemctl restart NetworkManager
sudo systemctl restart comitup
```

### Portal not accessible

```bash
# Check if web service is enabled
grep web_service /etc/comitup.conf

# Should show: web_service: true

# Check if comitup is listening
sudo netstat -tulpn | grep comitup
```

### Cannot connect to saved network

```bash
# List saved networks
nmcli connection show

# Test manual connection
sudo nmcli device wifi connect "YourSSID" password "YourPassword"

# Check NetworkManager logs
sudo journalctl -u NetworkManager -n 50
```

## Rollback (If Needed)

If you need to go back to the custom solution:

```bash
# Uninstall Comitup
sudo apt-get remove comitup
sudo apt-get autoremove

# Remove Comitup repository
sudo rm /etc/apt/sources.list.d/davesteele-comitup.list

# Reinstall custom solution
cd headless_wifi_connect
sudo bash install.sh
```

## FAQ

### Q: Will my saved WiFi networks be preserved?
**A:** Yes! Both solutions use NetworkManager, so your saved networks remain configured.

### Q: Can I use my camera app with Comitup?
**A:** Yes! Comitup just handles WiFi setup. Your camera app works normally once connected.

### Q: How do I change the AP name or password later?
**A:** Edit `/etc/comitup.conf` and restart: `sudo systemctl restart comitup`

### Q: Does Comitup support hidden networks?
**A:** Yes! The web interface allows manual SSID entry for hidden networks.

### Q: Can I use both WiFi interfaces (one for AP, one for client)?
**A:** Yes! Comitup supports dual WiFi interfaces. The first remains as hotspot, the second connects to external networks.

### Q: What if multiple devices use the same AP name?
**A:** Each device appends a unique ID (based on MAC address) to the AP name, making each unique.

### Q: How do I update Comitup?
**A:** Standard apt upgrade:
```bash
sudo apt-get update
sudo apt-get upgrade comitup
```

## Additional Resources

- **Comitup Documentation**: https://davesteele.github.io/comitup/
- **GitHub Repository**: https://github.com/davesteele/comitup
- **Issue Tracker**: https://github.com/davesteele/comitup/issues
- **Debian Package**: https://packages.debian.org/bookworm/comitup

## Support

If you encounter issues:

1. Check Comitup logs: `sudo journalctl -u comitup -f`
2. Review Comitup documentation
3. Search existing GitHub issues
4. Create new issue with logs and system info

---

**Migration completed? You now have a production-grade, stable WiFi provisioning system!** 🎉
