macOS 14以降。Apple Silicon / Intel対応のUniversalアプリです。

- `~/.ssh/config`、Include、conf.dの階層表示と編集
- ファイル名変更、ディレクトリ作成、読み込み元Includeの更新
- Hostをファイル間へドラッグして移動。ホバーで挿入位置を表示
- 保存前の差分確認、外部変更の検出、バックアップ

ZIPを展開し、SSHConfigEditor.appをApplicationsへ移動してください。

**Developer ID署名済み・未公証です。** 初回起動はmacOSにブロックされる場合があります。入手元と署名を確認したうえで、システム設定 → プライバシーとセキュリティの「このまま開く」から許可してください。SHA-256は同梱の `.sha256` ファイルで確認できます。

公証・Gatekeeperによる通常起動の保証、およびIntel実機での動作確認は未実施です。設定の優先順位はHostの順序やIncludeの展開順に依存するため、移動・名前変更後は保存前に差分を確認してください。
