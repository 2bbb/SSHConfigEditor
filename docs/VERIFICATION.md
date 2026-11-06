# 検証記録

2026-11-06、Apple Silicon / Swift 6.3.3。

## 自動検証

`swift test`：19件成功。

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

## ログと限界

D&Dの開始、ファイル進入、ドロップ、終了は設定本文を含めずOSLogへ記録する。

```sh
/usr/bin/log show --last 5m --style compact --predicate 'subsystem == "local.2bit.SSHConfigEditor" AND category == "drag"'
```

ドラッグソースの保持とUTTypeのInfo.plist登録後、実操作ログで `File drop committed` → `Native Host drag ended; operation=16` を確認。

ホバーの待機・挿入・キャンセルは状態テストで検証。GUI自動操作は継続的なマウス保持を指定できないため、長時間ホバーから任意位置への一連の操作の完全な自動再現には限界がある。

全OpenSSH構文の検証、通信、他のMacへの配布・公証は未実施。複数ファイルの書き換えをまたぐ原子性はない。
