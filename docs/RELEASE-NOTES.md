## Changes

- Use English throughout the interface, menus, dialogs, status messages, and diagnostics.
- Set English as the app's default language.
- Make README.md the English entry point and retain README_ja.md as the Japanese guide.

## Download

Requires macOS 14 or later. The Universal app supports Apple Silicon and Intel.

Extract the ZIP and move SSHConfigEditor.app to Applications. The app edits SSH configuration files, follows Include references, updates references when renaming files, and moves Host blocks between files using drag and drop.

**Developer ID signed; not notarized.** macOS may block the first launch. After verifying the download source and signature, allow the app in **System Settings → Privacy & Security → Open Anyway**. Verify the ZIP using the accompanying `.sha256` file.

Notarization, normal Gatekeeper acceptance, Intel hardware, and macOS 14 hardware have not been verified. Host and Include order affect configuration precedence; review changes before saving after a move or rename.
