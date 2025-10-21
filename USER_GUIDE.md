# RaspiCam Quick Start Guide

## What You Need
- Your RaspiCam device (Raspberry Pi with camera)
- Power supply (USB-C)
- Smartphone, tablet, or computer with WiFi

## Setup Steps

### 1. Power On
Connect the power supply to your RaspiCam. The device will take about 30-60 seconds to boot up.

### 2. Connect to Setup Network
On your phone or computer:
1. Open WiFi settings
2. Look for a network named **`RaspiCam-Setup-XXXX`**
   - (XXXX will be 4 unique characters)
3. Connect using password: **`raspberrypi`**

### 3. Configure WiFi
Once connected:
1. A setup page should open automatically
   - If not, open a web browser and go to: **`http://192.168.4.1`**
2. You'll see a list of available WiFi networks
3. Select your home/office WiFi network
4. Enter your WiFi password
5. Click **"Connect to Network"**

### 4. Done!
- The RaspiCam will connect to your WiFi
- The setup network will disappear
- Your camera is now ready to use!
- Access it through your camera app or web browser

## Finding Your Camera

After setup, find your camera at:
- By hostname: `http://raspicam.local`
- By IP address: Check your router's device list for "raspicam"

## Troubleshooting

### Setup network doesn't appear
- Wait 2 minutes after powering on
- Make sure the device has power (check LED lights)
- Try restarting the device

### Can't connect to setup network
- Make sure you're using password: `raspberrypi`
- Try forgetting the network and connecting again
- Move closer to the device

### Setup page doesn't open
- Try opening a web browser manually
- Go to: `http://192.168.4.1`
- Try a different browser

### WiFi connection fails
- Double-check your WiFi password
- Make sure your WiFi network is 2.4GHz or 5GHz compatible
- Move the device closer to your WiFi router
- The device will return to setup mode automatically - just try again

### Need to change WiFi network
If you need to connect to a different WiFi network:
1. Power off the device
2. Power it back on
3. Wait 2 minutes
4. If it can't connect to the previous network, setup mode will activate automatically
5. Follow the setup steps again

## Changing Networks Later

To connect to a different WiFi network:

**Option 1: Can't connect to old network**
- The device will automatically enter setup mode if it can't connect
- Just follow the setup steps again

**Option 2: Still connected to old network**
- You'll need to access the device via SSH or a monitor
- Or, move it out of range of the old network
- It will enter setup mode automatically

## Technical Specifications

- **Setup Network Name:** RaspiCam-Setup-XXXX
- **Setup Password:** raspberrypi
- **Setup IP Address:** 192.168.4.1
- **WiFi Standards:** 802.11b/g/n/ac
- **Security:** WPA2-PSK

## Support

For additional help:
- GitHub Issues: https://github.com/mokcontoro/headless_wifi_connect/issues
- Documentation: https://github.com/mokcontoro/headless_wifi_connect

## Safety Information

- Use only the provided power supply
- Keep device away from water
- Ensure adequate ventilation
- Do not open the device enclosure

---

**Thank you for choosing RaspiCam!**

Visit https://github.com/mokcontoro/headless_wifi_connect for tutorials, tips, and updates.
