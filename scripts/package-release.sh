#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Public releases require Developer ID. Notarization is intentionally deferred.
: "${SIGNING_IDENTITY:?Set the Developer ID Application identity}"
: "${EXPECTED_TEAM_ID:?Set the expected Developer ID team}"
[[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] || {
    echo 'A Developer ID Application identity is required.' >&2; exit 1;
}
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
label="${RELEASE_LABEL:-v$version}"
[[ "$label" == latest || "$label" == "v$version" ]] || {
    echo "Release label must be latest or v$version." >&2; exit 1;
}
stage=$(mktemp -d "${TMPDIR:-/tmp}/ssh-config-release.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/SSHConfigEditor.app"
UNIVERSAL=1 APP_OUTPUT="$app" bash scripts/build.sh

verify_app() {
    local bundle="$1" info
    codesign --verify --deep --strict --verbose=2 "$bundle"
    info=$(codesign -dv --verbose=4 "$bundle" 2>&1)
    printf '%s\n' "$info"
    [[ "$info" == *"Authority=$SIGNING_IDENTITY"* ]]
    [[ "$info" == *"TeamIdentifier=$EXPECTED_TEAM_ID"* ]]
    [[ "$info" == *"Timestamp="* && "$info" == *"runtime"* ]]
    lipo "$bundle/Contents/MacOS/SSHConfigEditor" -verify_arch arm64 x86_64
    [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$bundle/Contents/Info.plist")" == "$version" ]]
}
verify_app "$app"
mkdir -p artifacts/releases
archive="artifacts/releases/SSHConfigEditor-$label-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/release.zip"
ditto -x -k "$stage/release.zip" "$stage/extracted"
verify_app "$stage/extracted/SSHConfigEditor.app"
mv "$stage/release.zip" "$archive"
(
    cd artifacts/releases
    shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256"
)
printf 'Packaged: %s\n' "$archive"
