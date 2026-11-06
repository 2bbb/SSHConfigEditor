# SSH Config Editor

A native macOS editor for `~/.ssh/config` and included configuration files. Built with SwiftUI and AppKit, with no external package dependencies. The interface uses English by default.

[日本語](README_ja.md)

## Install

Download the Universal ZIP from the [stable release](https://github.com/2bbb/SSHConfigEditor/releases/latest) or the [latest development build](https://github.com/2bbb/SSHConfigEditor/releases/tag/latest). Extract it and move `SSHConfigEditor.app` to Applications.

Requires macOS 14 or later. Release builds include Apple Silicon and Intel binaries. They are **Developer ID signed but not notarized**. If macOS blocks the first launch, verify the download source, then use **System Settings → Privacy & Security → Open Anyway**. Each release includes a SHA-256 checksum.

The app opens `~/.ssh/config` by default. Opening a file does not change it.

## Build locally

Requires Xcode with a Swift 6 toolchain.

```sh
bash scripts/build.sh
open artifacts/SSHConfigEditor.app
```

By default, the script builds for the current Mac and uses an ad-hoc signature for local use. Set `UNIVERSAL=1` to build both architectures, or `SIGNING_IDENTITY` to sign with a Developer ID identity.

See the [release guide](docs/RELEASE.md) for CI, version updates, and ZIP verification.

## Use

- **Files:** Browse the directory hierarchy. Switch to **Include** to inspect nested references, source lines, conditions, expansion order, missing matches, and cycles.
- **Host list:** Search and select Host or Match blocks in the current file.
- **Fields / Source:** Edit common settings in the form or edit the entire source file. Comments, unknown directives, and repeated IdentityFile entries are preserved. Use Source for repeated directives and Match conditions.
- **Add Host (`⌘N`):** Append a Host block. **Add Configuration File** creates a split configuration and any needed Include directive as unsaved changes.
- **Save All (`⌘S`):** Save modified files. **Review Changes** shows the saved and edited content side by side.
- **Rename:** Right-click a file or use the pencil button. Save edits first. A name such as `hoge/bar` moves the file relative to its current directory, creating missing folders. Review the Include updates before applying the rename.
- **Move a Host:** Drag a Host row onto another file to append it. Hover over a file for about 0.7 seconds to open its block list and choose an insertion point. Both files remain unsaved until you save. Press Escape or drop outside the app to cancel.

## Includes and renaming

Relative Include paths in user configuration resolve from `~/.ssh`, not from the directory containing the referring file. `conf.d` is not loaded automatically by OpenSSH: it needs an Include directive. The app follows references recursively and also lists unreferenced files under `conf.d`.

Renaming updates Include directives in loaded files. Explicit references update only the relevant argument. A wildcard remains unchanged when it still matches the renamed file; otherwise, the original wildcard is preserved and the new path is added explicitly. Names containing spaces, multiple referring files, and Includes inside conditional blocks are supported.

References in unloaded configurations, shell scripts, or external tools are outside the update scope. Renaming stops for symbolic-link paths or unresolved `%` tokens. Renaming and moving Host blocks can change configuration precedence through wildcard expansion order or block order.

## Saving and recovery

Before saving, the app compares the file on disk with the version originally loaded. It refuses to overwrite conflicting changes. Existing symbolic links update their targets. Ordinary saves preserve existing POSIX permissions; new files use `0600` and new directories use `0700`.

Backups are stored outside Include paths at:

```text
~/Library/Application Support/SSHConfigEditor/Backups/<UUID>/
```

- `config`: The previous content, with permissions `0600`.
- `source.json`: The original path, resolved path, permissions, and save time.

To restore a backup, close the app, check the target in `source.json`, then restore the content from `config`. Backups are not automatically expired or deleted.

Each file is saved by an atomic rename from a temporary file in the same directory. Saving multiple files is not a single atomic transaction. On partial failure, the app reports how many files were saved and keeps the remaining edits. If an Include update fails during a rename, the app attempts to roll back completed writes and the move. It reports incomplete recovery when external changes or other errors prevent rollback.

## Scope and limitations

The app does not provide full OpenSSH syntax validation, calculate effective settings, or make SSH connections. Basic checks cover quotation marks, missing values, and the Port range. Host and Match conditions, including `Match exec`, are never executed. Conditional Includes are shown as references only.

Environment variables such as `${NAME}` and `~` are expanded. Connection-dependent `%` tokens remain unresolved. Private key files are rejected. Files must be UTF-8, with a maximum of 2 MB per file, 512 loaded files, and an Include depth of 32.

## Verification

```sh
swift test
```

Tests cover source preservation, Includes, save conflicts, backups, renaming, Host moves, and hover/cancel state. Targeted OpenSSH compatibility checks run `/usr/bin/ssh -G` only against temporary fixtures.

To inspect the UI without opening your real configuration:

```sh
open artifacts/SSHConfigEditor.app --args --config "$PWD/Demo/config" --include-base "$PWD/Demo"
```

Quit an existing instance first. Saving edits changes the sample files, so copy `Demo/` under `artifacts/` before testing edits.

See [implementation sources](docs/SOURCES.md) and [verification notes](docs/VERIFICATION.md), currently maintained in Japanese. Intel hardware and macOS 14 hardware have not been tested.

## Project layout

- `Sources/SSHConfigCore/`: Source parsing, Include traversal, safe writes, renaming, and Host moves.
- `Sources/SSHConfigEditor/`: Editing state and native macOS UI.
- `Tests/`: Targeted tests.
- `Resources/`, `scripts/`: App bundle resources, generated icon, and build scripts.
- `Demo/`: Sample configuration.
- `artifacts/`: Built app, release ZIPs, and local verification output.
- `docs/`: Source references, release instructions, and verification records.
