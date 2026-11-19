#!/bin/bash
set -e
cd "$(dirname "$0")"
APP="机械革命桌面组件.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/MechrevoWidget" main.swift -framework AppKit
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier com.local.MechrevoWidget "$APP" >/dev/null 2>&1 || true
echo "构建完成: $(pwd)/$APP"
