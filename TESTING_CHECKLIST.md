# Testing Checklist for Headless WiFi Connect

Use this checklist to verify the system works correctly before distributing to end users.

## Pre-Installation Tests

### System Requirements
- [ ] Raspberry Pi 5 confirmed
- [ ] Raspberry Pi OS Bookworm (Debian 12) installed
- [ ] NetworkManager present (`nmcli --version`)
- [ ] Python 3.11+ present (`python3 --version`)
- [ ] Internet access available (for package installation)

## Installation Tests

### Basic Installation
- [ ] Installation script runs without errors: `sudo bash install.sh`
- [ ] All files copied to `/opt/headless_wifi_connect/`
- [ ] Scripts installed to `/usr/local/bin/`
- [ ] Systemd services created and enabled
- [ ] Services start successfully after installation

### Service Status
```bash
sudo systemctl status wifi-portal
sudo systemctl status wifi-check
```
- [ ] wifi-portal.service is active (running)
- [ ] wifi-check.service is active (running)
- [ ] No error messages in logs

## Functional Tests

### Test 1: Initial AP Mode
**Scenario:** Fresh installation with no saved WiFi networks

1. [ ] Reboot the Raspberry Pi: `sudo reboot`
2. [ ] Wait 60 seconds
3. [ ] AP network appears: `RaspiCam-Setup-XXXX`
4. [ ] Can connect to AP with password `raspberrypi`
5. [ ] Device gets IP address (should be 192.168.4.x)
6. [ ] Portal loads at http://192.168.4.1
7. [ ] Network scan shows available WiFi networks
8. [ ] Networks sorted by signal strength

### Test 2: WiFi Configuration via Portal
**Scenario:** User configures WiFi through web portal

1. [ ] Connect to AP network
2. [ ] Open portal at http://192.168.4.1
3. [ ] Select a WiFi network from the list
4. [ ] Enter correct password
5. [ ] Click "Connect to Network"
6. [ ] Success message appears
7. [ ] AP network disappears within 10 seconds
8. [ ] Pi connects to configured WiFi network
9. [ ] Can SSH to Pi on new network: `ssh pi@raspicam.local`
10. [ ] Internet connectivity works: `ping 8.8.8.8`

### Test 3: Manual Network Entry
**Scenario:** User manually enters network details

1. [ ] Connect to AP network
2. [ ] Open portal
3. [ ] Click "Enter network manually"
4. [ ] Enter SSID manually
5. [ ] Enter password
6. [ ] Click "Connect to Network"
7. [ ] Successful connection

### Test 4: Hidden Network
**Scenario:** Connecting to a hidden network

1. [ ] Connect to AP network
2. [ ] Open portal
3. [ ] Click "Enter network manually"
4. [ ] Enter hidden network SSID
5. [ ] Enter password
6. [ ] Check "This is a hidden network"
7. [ ] Click "Connect to Network"
8. [ ] Successful connection to hidden network

### Test 5: Wrong Password
**Scenario:** User enters incorrect WiFi password

1. [ ] Connect to AP network
2. [ ] Select a network
3. [ ] Enter incorrect password
4. [ ] Click "Connect"
5. [ ] Error message displayed
6. [ ] AP mode remains active
7. [ ] Can try again with correct password
8. [ ] Second attempt succeeds

### Test 6: WiFi Connection Loss
**Scenario:** Pi loses connection to configured network

1. [ ] Pi connected to WiFi network
2. [ ] Turn off WiFi router or move Pi out of range
3. [ ] Wait 60 seconds
4. [ ] AP mode activates automatically
5. [ ] Can reconnect via portal
6. [ ] Restore WiFi router/range
7. [ ] Can configure and connect again

### Test 7: Multiple Network Priority
**Scenario:** Multiple networks configured with different priorities

1. [ ] Configure Network A with priority 200
   ```bash
   sudo configure_wifi.sh "NetworkA" "passwordA" 200
   ```
2. [ ] Configure Network B with priority 100
   ```bash
   sudo configure_wifi.sh "NetworkB" "passwordB" 100
   ```
3. [ ] Both networks in range
4. [ ] Pi connects to Network A (higher priority)
5. [ ] Turn off Network A
6. [ ] Pi switches to Network B
7. [ ] Turn on Network A
8. [ ] Pi switches back to Network A

### Test 8: Reboot Persistence
**Scenario:** WiFi settings persist across reboots

1. [ ] Configure WiFi network via portal
2. [ ] Successful connection
3. [ ] Reboot Pi: `sudo reboot`
4. [ ] Pi automatically connects to configured network
5. [ ] No AP mode activation (since WiFi connects)

### Test 9: Captive Portal Detection
**Scenario:** Various devices detect captive portal

Test with multiple device types:
- [ ] iPhone/iPad automatically shows portal
- [ ] Android phone automatically shows portal
- [ ] Windows laptop shows portal notification
- [ ] macOS shows portal notification
- [ ] Linux laptop can access via browser

### Test 10: Network Scanning
**Scenario:** Portal correctly scans and displays networks

1. [ ] Connect to AP
2. [ ] Open portal
3. [ ] Network list appears within 5 seconds
4. [ ] All nearby networks visible
5. [ ] Signal strength indicators accurate
6. [ ] Secured networks show lock icon
7. [ ] Click "Rescan Networks"
8. [ ] List refreshes successfully

## Command-Line Tests

### Manual WiFi Configuration
```bash
sudo configure_wifi.sh "TestNetwork" "testpassword123"
```
- [ ] Creates network profile
- [ ] Connects successfully
- [ ] Network saved for auto-connect

### List WiFi Profiles
```bash
sudo configure_wifi.sh --list
```
- [ ] Shows all saved networks
- [ ] Shows priorities
- [ ] Shows active connection

### Manual AP Setup
```bash
sudo setup_ap.sh
```
- [ ] Creates AP successfully
- [ ] Displays AP SSID and password
- [ ] AP is discoverable
- [ ] Can connect to AP

### Check WiFi Status
```bash
nmcli device status
nmcli connection show
```
- [ ] WiFi interface shown
- [ ] Connection status correct
- [ ] IP address assigned

## Log Tests

### Portal Logs
```bash
sudo journalctl -u wifi-portal -f
```
- [ ] No error messages
- [ ] Shows network scans
- [ ] Shows configuration attempts
- [ ] Clean startup

### WiFi Check Logs
```bash
sudo journalctl -u wifi-check -f
```
- [ ] Regular status checks logged
- [ ] Connection state changes logged
- [ ] No repeated errors
- [ ] Appropriate actions taken

## Performance Tests

### Portal Response Time
- [ ] Portal loads in < 2 seconds
- [ ] Network scan completes in < 5 seconds
- [ ] Form submission responds in < 1 second
- [ ] Connection attempt starts immediately

### Boot Time
- [ ] First boot to AP active: < 90 seconds
- [ ] Reboot to WiFi connected: < 60 seconds
- [ ] AP mode activation after disconnect: < 60 seconds

### Resource Usage
```bash
htop
```
- [ ] Python process uses < 50MB RAM
- [ ] CPU usage < 5% when idle
- [ ] No memory leaks during extended operation

## Security Tests

### Password Validation
- [ ] Rejects passwords < 8 characters
- [ ] Accepts passwords 8-63 characters
- [ ] Handles special characters in passwords
- [ ] Prevents XSS in network names

### Network Security
- [ ] AP uses WPA2-PSK encryption
- [ ] Default password documented
- [ ] Recommend changing default password
- [ ] No unencrypted credentials in logs

## Edge Cases

### Network Name Edge Cases
- [ ] Very long SSID (32 characters)
- [ ] SSID with spaces
- [ ] SSID with special characters
- [ ] SSID with unicode characters

### Concurrent Connections
- [ ] Multiple users connect to AP simultaneously
- [ ] Portal handles multiple requests
- [ ] Only one configuration succeeds
- [ ] Others receive appropriate message

### Rapid State Changes
- [ ] Quick WiFi on/off cycles
- [ ] Rapid AP connection/disconnection
- [ ] Router restart during configuration
- [ ] No system crashes or hangs

## Uninstallation Tests

### Clean Removal
```bash
sudo bash uninstall.sh
```
- [ ] Services stopped
- [ ] Services disabled
- [ ] Files removed from /opt/
- [ ] Scripts removed from /usr/local/bin/
- [ ] Systemd units removed
- [ ] WiFi configs preserved (optional)
- [ ] System remains stable

## User Experience Tests

### End-User Workflow
Simulate first-time user:
1. [ ] Device arrives powered off
2. [ ] User powers on device
3. [ ] User finds setup instructions clear
4. [ ] User successfully finds AP network
5. [ ] User successfully connects to AP
6. [ ] Portal interface is intuitive
7. [ ] Network selection is obvious
8. [ ] Password entry is straightforward
9. [ ] Success feedback is clear
10. [ ] Device becomes accessible on network
11. [ ] Total time < 5 minutes

### User Documentation
- [ ] README is clear and accurate
- [ ] Setup guide is comprehensive
- [ ] User guide is simple and friendly
- [ ] Troubleshooting section is helpful
- [ ] Examples are correct

## Distribution Readiness

### Master Image Preparation
- [ ] System fully configured
- [ ] All packages installed
- [ ] Services enabled and tested
- [ ] Camera app installed and working
- [ ] Unnecessary files removed
- [ ] Image size reasonable (< 8GB)

### Scaling Tests
- [ ] Clone image to 3+ SD cards
- [ ] Each device has unique AP name
- [ ] All devices work independently
- [ ] No conflicts when multiple devices nearby

## Final Checklist

Before distribution:
- [ ] All tests passing
- [ ] Documentation complete
- [ ] User guide finalized
- [ ] Support contact information added
- [ ] License file included
- [ ] Customizations applied (branding, SSID, password)
- [ ] Performance acceptable
- [ ] Security considerations addressed
- [ ] Master image created and backed up
- [ ] Distribution package assembled

## Test Results

**Date Tested:** _______________
**Tested By:** _______________
**Pi Model:** Raspberry Pi 5
**OS Version:** Bookworm (Debian 12)
**Result:** ☐ Pass ☐ Fail

**Notes:**
_______________________________________________________________________________
_______________________________________________________________________________
_______________________________________________________________________________

**Known Issues:**
_______________________________________________________________________________
_______________________________________________________________________________
_______________________________________________________________________________
