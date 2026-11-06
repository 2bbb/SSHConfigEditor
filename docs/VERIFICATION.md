# 検証記録

2026-11-06、Apple Silicon / Swift 6.3.3。

## 自動検証

`swift test`：19件成功。その後、実UIで見つかった古いブロック範囲の再描画クラッシュを回帰テストに追加し、`swift test --filter ConfigTests` の9件（追加1件を含む）に成功。

- 編集した値以外のコメント、未知の設定、CRLF、末尾改行の保持
- 複数IdentityFileの保護、Host名の入力途中でブロックを結合しないこと
- Includeの基準ディレクトリ、glob順序、循環、未保存ファイルの参照
- バックアップ原本・権限、シンボリックリンク保存、外部変更・新規衝突の拒否
- 保存した安全なfixtureを `/usr/bin/ssh -G` が読み取ること
- 複数参照元の名前変更、glob維持／新参照追加、書き込み失敗時の取り消し
- `hoge/bar` へのディレクトリ作成、参照更新、再読込後の階層表示
- Host単位の末尾移動・途中挿入、コメントの移動、Match境界・global先頭の保護
- 約0.7秒の遅延で対象ファイルを選択し、ドロップまで書き換えないこと、キャンセル時のタイマー解除

`swift build -c release` 成功。`plutil -lint Resources/Info.plist` 成功。ビルドスクリプトでapp bundleと生成アイコンを作成し、ad-hoc署名の `codesign --verify --strict` を確認。

## UIと実ファイル

操作による書き込みは `artifacts/UITest/` のサンプルのみ。ユーザーのSSH設定は読み取りのみ。

- 分割ファイル選択、Hostフォーム編集、原文表示、保存前比較、保存、Includeツリー展開を実操作で確認。
- 未保存で終了した際の保存／キャンセル／破棄を確認。
- ステータスバーによる下部ボタンの隠れを外側VStackで解消。Pickerの「編集方法」の折り返しをラベル非表示で解消。修正後の画面で確認。
- ネイティブD&Dでdev-webを別ファイル末尾へ移動し、双方を保存。ディスク上で元に残らず、移動先に1つだけ存在することを確認。
- production.settingsへの変更で既存globを残した新Includeが追加されたことを確認。
- `hoge/bar` への変更でconf.d/hogeが作られ、ファイルが階層表示され、Includeの新パスが更新されたことを画面とファイルで確認。
- 階層表示への変更後も、ネイティブD&Dでlab-*を別フォルダ内のファイル末尾へ移動し、移動先のHost選択が保持され、両ファイルを保存できることを確認。

## ログと限界

D&Dの開始、ファイル進入、ドロップ、終了は設定本文を含めずOSLogへ記録する。

```sh
/usr/bin/log show --last 5m --style compact --predicate 'subsystem == "local.2bit.SSHConfigEditor" AND category == "drag"'
```

UTTypeをInfo.plistに登録し、ドラッグ開始元を永続的なウインドウ内NSView、ソースdelegateを終了まで保持する構成とした。ドロップ側もNSDraggingDestinationで受け付ける。実操作で末尾移動と保存を確認。

検証中のクラッシュレポートで `ConfigDocument.occurrences` の `Range requires lowerBound <= upperBound` を確認。Host移動直後、削除される行のビューが古いブロック範囲と短くなった原文を組み合わせて描画していた。範囲アクセスを安全化し、フォーム書き込み先も選択中ファイルではなくそのフォームの所有ファイルに固定した。回帰テストと修正後のネイティブD&Dを確認。

ホバーの待機・挿入・キャンセルは状態テストで検証。GUI自動操作は継続的なマウス保持を指定できないため、長時間ホバーから任意位置への一連の操作の完全な自動再現には限界がある。

全OpenSSH構文の検証、通信、公証は未実施。複数ファイルの書き換えをまたぐ原子性はない。

## v0.0.1 配布検証

2026-11-06、20テスト成功。Universal (arm64 / x86_64) ReleaseビルドとDeveloper ID署名、Hardened Runtime・secure timestamp、ZIP展開後の署名・Team ID・version・両architectureを検証。公証はユーザー指定で今回の対象外。Intel実機とmacOS 14実機での確認は未実施。公開用CIとダウンロード後の確認方法は `RELEASE.md` に記載。

## v0.0.2 英語UI

2026-11-06、アプリ内のラベル・ヘルプ・診断・エラー文言、ネイティブメニューとダイアログを英語化。Info.plistの既定言語と対応言語はen。署名済みReleaseビルドを起動し、日本語環境のMacでもFile/Editなど標準メニューとアプリ内表示が英語になることを確認。メイン画面、Fields/Source切り替え、名前変更ダイアログの長いボタンが表示幅に収まり、同名入力のエラーが英語で出ることを確認。名前変更はキャンセルし、実設定への書き込みは行っていない。READMEと配布案内は英語、既存の日本語READMEはREADME_ja.mdへ移動。
