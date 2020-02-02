# Clutch
Interface binding for Transmission (Mac)

This app allows you to send your torrent traffic over a VPN _interface_ (not just an IP). This means you can bind to /dev/utun0 instead of just binding to its IP address, and the binding IP will automatically update in the background.

For several years I had been using an app called Vuze because it was the only app for Mac that offered "connection binding," where I could send traffic over my VPN _interface_ (not just its IP address). I hated Vuze and wanted to use the Transmission app instead, but Vuze was the only app that offered binding for interfaces.

So I finally wrote an app called Clutch to add this feature to Transmission! It is a separate app so you don't have to worry about patching, and it will continue to work when new updates to Transmission are released.

## How does it work?

Transmission has a hidden option in its preferences file called "BindAddressIPv4" (and IPv6), which allows you to bind Transmission to an IP address. This is a nice feature, but it's a major inconvenience to have to update this address every time you start a new VPN connection and the binding IP address changes. Clutch takes care of this for you!

The app has 2 parts:

* Clutch is the GUI part of the app and allows you to select the interface you want to bind Transmission to.
* Clutch Agent runs in the background (it has an icon in the menu bar) and monitors the IP address of the binding interface. When the IP address changes, it will update the binding IP address in Transmission's preferences and restart Transmission if it was running. There is also an option to start Clutch Agent automatically when you log in.

## Download

You can download the app here (move it to your Applications folder):

https://github.com/hbwhite/Clutch/releases/download/v1.4/Clutch-v1.4.zip

## Changelog

v1.4:
- Clutch can now restart Transmission gracefully without using force-quit. This prevents you from losing your progress or torrent settings when Clutch has to restart Transmission. Enable this feature in Clutch for setup instructions.
- Added regex support for interface names. Be sure to use real regex and not shell glob. For example, enter utun.* instead of utun* if you want to use regex.
- Added a nice loading animation while Transmission is binding/unbinding
- Clutch now updates the list of interfaces each time you open the dropdown
- Fixed a bug where Transmission wouldn't restart if the bar menu was open
- Clutch now uses the new Mac OS hardened runtime
- Other minor bug fixes and performance improvements

v1.3:
- Clutch now restarts Transmission if your binding interface disappears and reappears. This fixes an issue where Transmission would fail to bind to your VPN if it started before the interface was online (this could happen on boot if Transmission opened before your VPN started)
- Adds support for automatic updates within Clutch. You can also select Clutch > Check for Updates... from the menu bar to manually update the app

v1.2:
- Support for Dark Mode (colors have been adjusted to work in both Light and Dark Mode)
- You can now resize the window (uses AutoLayout so the UI is perfect)
- Other UI improvements

v1.1:
- Clutch now treats interfaces with the same name but different IPv4/IPv6 statuses as separate interfaces, preventing any traffic from accidentally being sent in the clear if a VPN doesn't support IPv6.

v1.0:
- Initial release

## Archives

v1.3:
https://mega.nz/#!2BYHGYJS!TYZUOT01O2uTzYF870uWt48NC5NsFSGUv5V9ZtJ8qW4

v1.2:
https://mega.nz/#!2IAXUYJL!jN7EBqaT9mFQI0SjDl-rE7ISlM_zmiYatGhfLqjxT9c

v1.1:
https://mega.nz/#!qEh1AQQY!TK2gStUVWhaSG_hB-G_NSLjg2pcS8PEW4Jz1pYOyS5I

v1.0:
https://mega.nz/#!PYoQHKpY!ID4wO3XDzjfmsGqFws1AdiOT3PVkyRw7fbn3h7ZQXpc
