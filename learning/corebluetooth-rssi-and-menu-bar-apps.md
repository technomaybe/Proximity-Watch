# CoreBluetooth, RSSI, and Menu Bar Apps

Notes from building Proximity Watch.

## RSSI is a rough distance

RSSI (Received Signal Strength Indicator) is how loud a Bluetooth signal is, in dB. It's always negative. Closer to zero means stronger: -45 is the watch on your wrist at the keyboard, -75 is a few meters away, -90 is barely there.

Single readings bounce around a lot because your body, walls, and the way you're facing all block the signal. That's why `WatchMonitor` averages the last five readings before it decides anything.

## Why it can find your watch at all

Apple devices change their Bluetooth address every 15 minutes or so for privacy. A random app can't follow a device across those changes. Your Mac can, because it's signed in to the same Apple ID as your watch and holds the key (the IRK) that decodes the rotating address. So CoreBluetooth hands the app the same identifier for your watch every time.

## Hysteresis: two thresholds instead of one

If "near" and "away" used the same number, a signal hovering at -75 would flip back and forth every second. The app needs the signal 5 dB stronger than the lock threshold before it arms. That gap is called hysteresis, and thermostats use the same trick.

## The arm-then-lock rule

The app only arms after it has seen the watch nearby while you were typing or moving the mouse in the last 30 seconds. If you sit down without your watch, it never arms, so it can't lock you out. After it locks the Mac, it goes back to waiting and re-arms once you're back at the keyboard with the watch.

## Menu bar apps in SwiftUI

`MenuBarExtra` is the SwiftUI scene for an icon in the menu bar. Setting `LSUIElement` to YES in the Info.plist hides the Dock icon, so the app lives only up there. In this project that setting lives in Build Settings as `INFOPLIST_KEY_LSUIElement`, because Xcode generates the Info.plist for us.

## Building without changing xcode-select

`xcode-select -p` showed the Command Line Tools, not Xcode, so `xcodebuild` refused to run. Setting `DEVELOPER_DIR` for one command points it at Xcode without touching the system setting:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ~/Documents/Claude/Projects/Proximity-Watch/ProximityWatch.xcodeproj -scheme ProximityWatch build
```

To make Xcode the default for good (needs your password):

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```
