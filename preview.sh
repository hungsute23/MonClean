#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swiftc -swift-version 5 -target arm64-apple-macos13.0 -o /tmp/mcpreview \
    Sources/SystemMonitor.swift Sources/SMC.swift Sources/LaunchAtLogin.swift Sources/MonitorView.swift Sources/IconView.swift Preview/icon.swift Preview/main.swift
if [ $# -eq 0 ]; then /tmp/mcpreview /tmp/preview.png; else /tmp/mcpreview "$@"; fi
