#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="build/实时字幕播放器.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
swiftc -parse-as-library Sources/*.swift -o "$app/Contents/MacOS/CaptionPlayer" -framework SwiftUI -framework AVKit -framework Speech -framework ScreenCaptureKit -framework CoreMedia -O
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
printf 'Built: %s\n' "$app"
