#!/bin/bash
# Dựng AppIcon.icns từ IconView.swift
set -euo pipefail
cd "$(dirname "$0")"
./preview.sh --icon /tmp/icon1024.png >/dev/null
SET=/tmp/MonClean.iconset
rm -rf "$SET"; mkdir -p "$SET"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
    set -- $spec
    sips -z "$1" "$1" /tmp/icon1024.png --out "$SET/icon_$2.png" >/dev/null 2>&1
done
mkdir -p Resources
iconutil -c icns "$SET" -o Resources/AppIcon.icns
rm -rf "$SET"
echo "Đã tạo Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1))"
