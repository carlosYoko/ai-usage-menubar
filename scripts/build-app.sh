#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP_NAME="AI Usage Menubar"
APP_PATH="$ROOT/dist/$APP_NAME.app"

cd "$ROOT"
swift build --configuration "$CONFIG" --product AIUsageMenubar
BIN_PATH="$(swift build --configuration "$CONFIG" --show-bin-path)"
RESOURCE_BUNDLE="$BIN_PATH/AIUsageMenubar_AIUsageMenubar.bundle"

if [[ ! -x "$BIN_PATH/AIUsageMenubar" ]]; then
  echo "Missing executable: $BIN_PATH/AIUsageMenubar" >&2
  exit 1
fi
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Missing SwiftPM resource bundle: $RESOURCE_BUNDLE" >&2
  exit 1
fi

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/AIUsageMenubar" "$APP_PATH/Contents/MacOS/AIUsageMenubar"
# Put images in the standard app resource directory so the signed .app has no loose root contents.
cp "$RESOURCE_BUNDLE/CodexLogo.png" "$APP_PATH/Contents/Resources/CodexLogo.png"
cp "$RESOURCE_BUNDLE/CopilotLogo.png" "$APP_PATH/Contents/Resources/CopilotLogo.png"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"

cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>AIUsageMenubar</string>
    <key>CFBundleIdentifier</key><string>com.carlosYoko.ai-usage-menubar</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>AI Usage Menubar</string>
    <key>CFBundleDisplayName</key><string>AI Usage Menubar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --deep --sign - "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
printf 'Built app: %s\n' "$APP_PATH"
