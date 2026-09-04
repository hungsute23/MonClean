#!/bin/bash
# Dựng MonClean.app — app thanh menu, không có icon ở Dock.
set -euo pipefail
cd "$(dirname "$0")"

APP="MonClean.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>MonClean</string>
    <key>CFBundleDisplayName</key>       <string>MonClean</string>
    <key>CFBundleIdentifier</key>        <string>me.monstudio.monclean</string>
    <key>CFBundleExecutable</key>        <string>MonClean</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSUIElement</key>               <true/>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
</dict>
</plist>
PLIST

if [ -f Resources/AppIcon.icns ]; then
    mkdir -p "$APP/Contents/Resources"
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

swiftc -O -swift-version 5 \
    -target arm64-apple-macos13.0 \
    -o "$APP/Contents/MacOS/MonClean" \
    Sources/*.swift

codesign --force --sign - "$APP" 2>/dev/null || true

# Cài vào ~/Applications: đó là nơi login item trỏ tới, nên bản đang chạy
# luôn là bản mới nhất chứ không phải bản cũ nằm trong thư mục dev.
DEST="${MONCLEAN_DEST:-/Applications}/MonClean.app"
pkill -x MonClean 2>/dev/null || true
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -R "$APP" "$DEST"
echo "Đã dựng $APP  →  cài vào $DEST"
