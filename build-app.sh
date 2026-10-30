#!/bin/zsh
# Builds "Just Say It.app" and installs it to ~/Applications.
# Created by Stefano Roman Gunness · MIT License
set -e
cd "$(dirname "$0")"

swift build -c release

APP="build/Just Say It.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/JustSayIt "$APP/Contents/MacOS/JustSayIt"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Just Say It</string>
  <key>CFBundleDisplayName</key><string>Just Say It</string>
  <key>CFBundleIdentifier</key><string>com.stefano.justsayit</string>
  <key>CFBundleExecutable</key><string>JustSayIt</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>11</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Stefano Roman Gunness. MIT License.</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Just Say It listens to your voice to type for you. Audio never leaves your Mac.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Just Say It turns your speech into text on-device.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Just Say It reads your calendar to join your Zoom, Google Meet and Teams calls and take notes.</string>
  <key>NSAppleEventsUsageDescription</key><string>Just Say It types text into the app you are using.</string>
</dict>
</plist>
PLIST

# App icon (generated once from the SF Symbol renderer script).
if [ ! -f build/AppIcon.icns ]; then
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a stable local identity so macOS keeps the permissions across rebuilds.
./scripts/make-signing-identity.sh >/dev/null
cat > build/entitlements.plist <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.automation.apple-events</key><true/>
  <key>com.apple.security.device.audio-input</key><true/>
  <key>com.apple.security.personal-information.calendars</key><true/>
</dict></plist>
ENT
codesign --force --options runtime --entitlements build/entitlements.plist \
  --sign "Just Say It Local Signing" --keychain "$HOME/Library/Keychains/justsayit-signing.keychain-db" \
  --identifier com.stefano.justsayit "$APP"

[ -n "$JUSTSAYIT_UPDATER" ] || pkill -x JustSayIt 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/"Just Say It.app"
cp -R "$APP" ~/Applications/
rm -rf "$APP"
echo "Installed: ~/Applications/Just Say It.app"
