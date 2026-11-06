#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_args=(-c release)
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    build_args+=(--arch arm64 --arch x86_64)
fi
swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
app="${APP_OUTPUT:-artifacts/SSHConfigEditor.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/artwork
cp "$bin_dir/SSHConfigEditor" "$app/Contents/MacOS/SSHConfigEditor"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/generate-icon.swift .build/artwork/AppIcon.iconset
iconutil -c icns .build/artwork/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
if [[ "${SIGNING_IDENTITY:--}" == - ]]; then
    codesign --force --sign - "$app"
else
    codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$app"
fi
codesign --verify --deep --strict "$app"
printf 'Built: %s\n' "$app"
