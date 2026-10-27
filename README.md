# Proximity Watch

A macOS menu bar app that locks your Mac when your Apple Watch walks away.

It only arms after it has seen your watch nearby while you were using the Mac. If you sit down without your watch, it never arms, so it can't lock you out. After it locks, unlock the usual way (password, Touch ID, or Apple Watch Auto Unlock) and it re-arms once you're back at the keyboard with your watch.

## How it works

The app reads your watch's Bluetooth signal strength (RSSI) every second and averages the last five readings. When the signal stays below your lock threshold for the delay you set, it locks the screen. Your Mac can follow the watch's rotating Bluetooth address because both are signed in to the same Apple ID.

See [learning/corebluetooth-rssi-and-menu-bar-apps.md](learning/corebluetooth-rssi-and-menu-bar-apps.md) for more detail.

## Requirements

- macOS 14 or later
- Xcode 16 or later
- An Apple Watch signed in to the same Apple ID as the Mac

## Build and run

Open `ProximityWatch.xcodeproj` in Xcode and press Command-R. Allow Bluetooth when macOS asks. Click the watch icon in the menu bar, choose **Choose your watch…**, hold the watch against the Mac, and pick the strongest signal.

## Settings

- **Lock threshold:** the signal level, in dB, that counts as walked away. The default is -75. Move it toward -65 to lock sooner, or toward -85 to lock later.
- **Delay:** how many seconds the watch has to stay away before the Mac locks. The default is 10.

## License

MIT. See [LICENSE](LICENSE).
