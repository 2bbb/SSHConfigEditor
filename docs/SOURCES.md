# 仕様と判断

確認日：2026-11-06。

- [OpenSSH ssh_config(5)](https://man.openbsd.org/ssh_config)：先に得られた値の優先、Host/Match、Includeの基準パスとlexical order、環境変数・トークン。
- [OpenSSH argv_split](https://github.com/openssh/openssh-portable/blob/master/misc.c)：引用符・エスケープの扱い。アプリは原文を保持する限定的な索引で、OpenSSH評価器の再実装ではない。
- [Apple NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)：3ペインのファイル／ブロック／詳細構成。
- [Apple NSDraggingSource](https://developer.apple.com/documentation/appkit/nsdraggingsource)：ネイティブD&Dの終了通知。ローカルmacOS SDKの `NSDragging.h` と `NSView.h` で署名を確認。

`ssh -G` でも `Match exec` が実行されうるため、実ユーザー設定を評価しない。フォームは現在のブロックに書かれた値のみを表示する。

ステータスバーをNavigationSplitViewのsafeAreaInsetに置くと下端のボタンに重なる実表示を確認した。外側のVStackで独立した高さを確保した。狭いセグメントPickerには `.labelsHidden()` を適用し、ラベルの不自然な折り返しを除去した。

名前変更は読み込み済み設定全体を検索して参照を書き換える。未解決の接続依存Includeは推測しない。Host移動は未保存の編集であり、移動前後の比較と通常の競合チェックを通す。
