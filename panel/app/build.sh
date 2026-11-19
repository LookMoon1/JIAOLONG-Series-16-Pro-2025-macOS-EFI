#!/bin/bash
set -e
cd "$(dirname "$0")"
APP="机械革命性能面板.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/MechrevoPanel" main.swift -framework AppKit
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier com.local.MechrevoPanel "$APP" >/dev/null 2>&1 || true
echo "构建完成: $(pwd)/$APP"
