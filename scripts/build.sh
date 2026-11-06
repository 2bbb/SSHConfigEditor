#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app="artifacts/SSHConfigEditor.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/artwork
cp "$bin_dir/SSHConfigEditor" "$app/Contents/MacOS/SSHConfigEditor"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/generate-icon.swift .build/artwork/AppIcon.iconset
iconutil -c icns .build/artwork/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SIGNING_IDENTITY:--}" "$app"
codesign --verify --strict "$app"
printf 'Built: %s/%s\n' "$PWD" "$app"
