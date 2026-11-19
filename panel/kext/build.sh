#!/bin/bash
# 构建 MechrevoEC.kext（仅用 Command Line Tools，无需 Xcode）
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --show-sdk-path)"
KINC="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
OUT="$HERE/MechrevoEC.kext"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"

clang++ -arch x86_64 -mkernel -nostdlib -r \
  -fno-rtti -fno-exceptions -fno-common -fno-builtin \
  -O2 -Wall \
  -isysroot "$SDK" -I"$KINC" \
  -Wl,-kext \
  "$HERE/MechrevoEC.cpp" -o "$OUT/Contents/MacOS/MechrevoEC"

cp "$HERE/Info.plist" "$OUT/Contents/Info.plist"

codesign --force --sign - --identifier com.local.MechrevoEC "$OUT" 2>/dev/null || true

echo "built: $OUT"
ls -l "$OUT/Contents/MacOS/MechrevoEC"
