# 配布手順

GitHub: https://github.com/2bbb/SSHConfigEditor

## 配布契約

- ZIP内に `SSHConfigEditor.app` 1個。macOS 14以降、arm64 / x86_64 Universal。
- `Developer ID Application: ISHII 2BIT PROGRAM OFFICE (RS3AQSY9YN)` で署名。Hardened Runtime・タイムスタンプあり。追加entitlements・同梱helper・外部frameworkなし。
- 2026-11-06のユーザー指定により、当面はDeveloper ID署名のみで公開。公証・stapleは未実施。Gatekeeperが初回起動を拒否しうるため、Releaseに明記。
- アプリのバージョンは `Resources/Info.plist` の `CFBundleShortVersionString` を正とし、正式タグは `v<version>` と一致させる。

## GitHub Actions

`.github/workflows/macos.yml` はmacOS 15 / Xcode 26.3で実行する。

| トリガー | 結果 |
| --- | --- |
| Pull Request | テスト・Universalビルド。署名用Secretsなし |
| mainへのpush / mainの手動実行 | 検証後、Developer IDで再ビルドし `latest` prereleaseを更新 |
| `v*` タグpush | 検証後、同名の正式Releaseを作成 |

`latest` は移動するタグで、正式版のGitHub `/releases/latest` とは異なる。正式版はタグと同名のZIPを保持し、既存Releaseを上書きしない。

必要なRepository Actions Secrets:

- `MACOS_CERTIFICATE_P12_BASE64`：対象Developer IDと秘密鍵だけを含む、パスワード付きPKCS#12のBase64
- `MACOS_CERTIFICATE_PASSWORD`：そのエクスポートパスワード

SecretsをPRへ渡さず、公開jobのみ `contents: write` を持つ。証明書は使い捨てkeychainへ取り込み、終了時に削除する。保護対象の秘密鍵、証明書、パスワードをリポジトリに保存しない。

## バージョン公開

1. Info.plistのバージョンと `docs/RELEASE-NOTES.md` を更新してmainへpush。
2. mainのCI成功とlatest ZIPを確認。
3. `git tag -a v0.0.1 -m 'Release v0.0.1'`、`git push origin v0.0.1`。
4. タグのActions成功、ReleaseのZIPとSHA-256を確認。

ローカルで同じZIPを作成:

```sh
SIGNING_IDENTITY='Developer ID Application: ISHII 2BIT PROGRAM OFFICE (RS3AQSY9YN)' \
EXPECTED_TEAM_ID=RS3AQSY9YN bash scripts/package-release.sh
```

成果物は `artifacts/releases/SSHConfigEditor-v0.0.1-macOS-universal.zip` と `.zip.sha256`。`RELEASE_LABEL=latest` でlatest名になる。生成処理は両architecture、署名者・Team ID、Hardened Runtime・timestamp、バージョンを検査し、ZIPを新しい一時ディレクトリへ展開して再検証する。

ダウンロード後、同じフォルダで:

```sh
shasum -a 256 -c SSHConfigEditor-v0.0.1-macOS-universal.zip.sha256
codesign --verify --deep --strict SSHConfigEditor.app
codesign -dv --verbose=4 SSHConfigEditor.app
```

署名検証は公証や実機の動作確認を代替しない。Intel実機確認、macOS 14実機確認、公証は未実施。

## 根拠

- [Apple Developer ID](https://developer.apple.com/developer-id/) — Developer ID署名と公証の区別。
- [Apple Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — 将来の公証追加時はAccepted → staple → 最終ZIP再生成の順に実施。
- [GitHub macOS runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) と [macOS 15 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md) — runner・Xcode選定（2026-11-06確認）。
