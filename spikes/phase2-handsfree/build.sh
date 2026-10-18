#!/bin/bash
# Builds the Bluetooth hands-free spike as a small app bundle, so macOS can
# ask for Bluetooth permission (a bare executable would borrow the terminal's).
set -euo pipefail
cd "$(dirname "$0")"
APP="build/HandsFreeSpike.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -swift-version 5 -O -o "$APP/Contents/MacOS/HandsFreeSpike" Sources/main.swift \
    -framework IOBluetooth -framework CoreAudio -framework SwiftUI -framework AppKit
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.julianamarques.galaxybridge.spike.handsfree</string>
    <key>CFBundleName</key><string>HandsFreeSpike</string>
    <key>CFBundleExecutable</key><string>HandsFreeSpike</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSBluetoothAlwaysUsageDescription</key><string>Para testar o Mac como viva-voz do Galaxy.</string>
    <key>NSMicrophoneUsageDescription</key><string>Para mandar sua voz para a ligação.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Pronto: $APP"
