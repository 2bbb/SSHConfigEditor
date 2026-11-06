# Release guide

Repository: https://github.com/2bbb/SSHConfigEditor

## Distribution

- Each ZIP contains one `SSHConfigEditor.app`, targeting macOS 14 or later with arm64 and x86_64 binaries.
- The app is signed with `Developer ID Application: ISHII 2BIT PROGRAM OFFICE (RS3AQSY9YN)`, with Hardened Runtime and a secure timestamp. It has no extra entitlements, bundled helpers, or external frameworks.
- Releases are intentionally **not notarized**, as requested on 2026-11-06. Gatekeeper may block the first launch; the release notes explain this limitation.
- `CFBundleShortVersionString` in `Resources/Info.plist` is the version source of truth. Stable tags must match `v<version>`. Increment `CFBundleVersion` for each release.

## GitHub Actions

`.github/workflows/macos.yml` runs on macOS 15 with Xcode 26.3.

| Trigger | Result |
| --- | --- |
| Pull request | Tests and Universal build, without signing secrets |
| Push to main / manual run on main | Validation, Developer ID build, and an updated `latest` prerelease |
| `v*` tag push | Validation and a stable release matching the tag |

`latest` is a moving development tag, distinct from GitHub's `/releases/latest` URL for the newest stable release. Stable releases keep their versioned ZIPs and are never overwritten by CI.

Required repository Actions secrets:

- `MACOS_CERTIFICATE_P12_BASE64`: Base64-encoded, password-protected PKCS#12 containing only the selected Developer ID certificate and private key.
- `MACOS_CERTIFICATE_PASSWORD`: The export password.

Pull requests receive no signing secrets. Only the release job has `contents: write`. The certificate is imported into a temporary keychain and removed at the end of the job. Never commit certificates, private keys, or passwords.

## Publish a version

1. Update the version in Info.plist and `docs/RELEASE-NOTES.md`, then push to main.
2. Confirm main CI succeeds and inspect the latest ZIP.
3. Create and push the version tag, for example:

   ```sh
   git tag -a v0.0.2 -m 'Release v0.0.2'
   git push origin v0.0.2
   ```

4. Confirm the tag's Actions run succeeds and the release contains the ZIP and SHA-256 file.

To create the same ZIP locally:

```sh
SIGNING_IDENTITY='Developer ID Application: ISHII 2BIT PROGRAM OFFICE (RS3AQSY9YN)' \
EXPECTED_TEAM_ID=RS3AQSY9YN bash scripts/package-release.sh
```

Output: `artifacts/releases/SSHConfigEditor-v0.0.2-macOS-universal.zip` and `.zip.sha256`. Set `RELEASE_LABEL=latest` for the development filename. Packaging checks both architectures, signing authority, Team ID, Hardened Runtime, timestamp, and version, then extracts the final ZIP into a fresh directory and verifies it again.

After downloading, run these commands in the download directory:

```sh
shasum -a 256 -c SSHConfigEditor-v0.0.2-macOS-universal.zip.sha256
codesign --verify --deep --strict SSHConfigEditor.app
codesign -dv --verbose=4 SSHConfigEditor.app
```

Signature checks do not replace notarization or hardware testing. Intel hardware, macOS 14 hardware, and notarization remain unverified.

## References

- [Apple Developer ID](https://developer.apple.com/developer-id/): Developer ID signing and notarization.
- [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution): When adding notarization, require acceptance, staple the app, rebuild the final ZIP, and verify its extracted contents.
- [GitHub macOS runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [macOS 15 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md): Runner and Xcode selection, checked on 2026-11-06.
