#!/bin/bash
set -euo pipefail
umask 077
: "${RUNNER_TEMP:?}"
: "${GITHUB_ENV:?}"
: "${MACOS_CERTIFICATE_P12_BASE64:?Developer ID certificate secret is missing}"
: "${MACOS_CERTIFICATE_PASSWORD:?Certificate password secret is missing}"

certificate="$RUNNER_TEMP/developer-id.p12"
keychain="$RUNNER_TEMP/ssh-config-signing.keychain-db"
password=$(openssl rand -hex 32)
trap 'rm -f "$certificate"' EXIT
printf '%s' "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$certificate"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$certificate" -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain"
security set-key-partition-list -S apple-tool:,apple: -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain"
security find-identity -v -p codesigning "$keychain"
