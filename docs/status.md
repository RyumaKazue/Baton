# 開発の状況（引き継ぎ用）

最終更新：2026-10-20（v0.2 リリース後）

会話のコンテキストをクリアしても続きから再開できるように、今の状況と、次にやること、決まっていないことをまとめる。計画の全体は [plan.md](plan.md)、MVP の範囲は [mvp.md](mvp.md) を参照。

## 1. 今どこにいるか

**v0.2 をリリースした（2026-10-20、タグ `v0.2`、GitHub の Release「Baton v0.2」）。** `/Applications` に v0.2 を入れてある。次に何を作るかは未定。

| フェーズ | 内容 | 状態 |
|---|---|---|
| 0〜5 | MVP（v0.1）。2026-10-08 にリリース | ✅ |
| 6 | 離れている間は手放し続ける（#41） | ✅ |
| 7 | 出力先の切り替え（#46） | ✅ |
| 8 | 再生中は接続を維持（#49） | ✅ |
| 9 | アイコンと仕上げ（#58）、v0.2 のリリース（#60） | ✅ |

v0.2 の途中で、ほかに入れたもの

- 設定を、メニューの右上の歯車で開く画面に分けた（#55）。説明の文は「再生中は接続を維持」の下だけ（#61）
- 接続に失敗したときのメッセージを、メニューを閉じたら消す（#53）
- 不具合 #51：電池切れの深いスリープから起きると bluetoothd が起動し直し、Baton の中の Bluetooth の部品が壊れる。CoreBluetooth の状態（resetting → poweredOn）で気づいて、Baton が自分で起動し直す（#57）。`sudo killall bluetoothd` で再現でき、確認済み（受け入れテスト K4）
- 接続・切断の時間切れのタイマーの不具合（#43）、通知が届かないときの読み直し（#54）

## 2. v0.2 のリリース（#60）

| 作業 | 状態 |
|---|---|
| バージョン 0.2、リリースノート（[releases/v0.2.md](releases/v0.2.md)）、docs（#62） | ✅ |
| 受け入れテスト J・L | ✅ 2026-10-20 |
| `/Applications` に入れる | ✅ |
| `v0.2` のタグと GitHub の Release | ✅ 2026-10-20 |

## 3. 決まっていないこと

| # | 項目 | 選択肢 | 状況 |
|---|---|---|---|
| 1 | bluetoothd の起動し直しの安全弁の穴：Baton が起動して30秒以内に bluetoothd が起動し直すと、起動し直さずに壊れたまま動き続ける | — | **決定（2026-10-20）**：まれなので見送る。起きたら、Baton を手で起動し直す（リリースノートの既知の制約に書いた） |
| 2 | 検証2：外部モニターと電源につないだまま、再生しながらふたを閉じたとき、どの通知が届くか | — | 未実施（受け入れテスト I8） |

## 4. 進め方の約束

- 実装は Claude がすべて行い、ユーザーはコードの理解に集中する（2026-10-02 から）
- Issue → ブランチ → Pull Request → CI → マージの流れ。`main` は保護されていて、CI（Test BatonKit、Build BatonMac）が通らないとマージできない
- Issue・Pull Request の作成、push、マージは Claude が `gh` で行える。**マージはユーザーの OK をもらってから**行う
- 実機での確認（Bluetooth、スリープ、ロックなど）はユーザーが行い、Claude は電源ログやアプリのログで裏付けを取る

## 5. つまずきやすい点

| 点 | 内容 |
|---|---|
| `log` コマンド | zsh には同じ名前の組み込みコマンドがある。macOS のログを見るときは `/usr/bin/log` と書く |
| 本当にスリープしたか | 電源ログ `pmset -g log` の `Sleep` の行で確かめる。`Display is turned off` だけなら、画面が消えただけ。スリープを止めているものは `pmset -g` の「sleep prevented by」で分かる |
| ブランチの切り替え | Xcode を開いたまま切り替えると、Xcode が古いプロジェクトの設定を書き戻すことがある。閉じておくか、「Revert」を選ぶ |
| CI でのテスト | テストの本体（Baton.app）が本物の Bluetooth に触ると、CI で許可のダイアログが出て止まる。`BatonMac` スキームの Test では `BATON_MOCK_BLUETOOTH=1` を渡している |
| 同じアプリが2つ | Xcode から起動した開発中のアプリと、`/Applications` のアプリを同時に動かさない（同じ Bundle ID。メニューバーのアイコンが2つになり、両方がスリープ時の処理をする） |
| 検証用のブランチ | `spike/iobluetooth`、`spike/40-dark-wake-disconnect`、`spike/51-relaunch-on-bluetooth-reset` はローカルにだけある（main にはマージしない） |
| ログの混ざり | `subsystem == "com.furiel05.AudioAutoConnect"` のログには、テストの実行（ダミー）のログも混ざる。調べるときは `processID` で絞る。ログは数日で消える |
| Bluetooth が急に動かない | まず bluetoothd が起動し直していないか（`ps -o lstart -p $(pgrep -x bluetoothd)`、`pmset -g log` の `Wake from Hibernate`）と、bluetoothd 側のログ（`ACL connected ... status`）を見る。ヘッドホンの電源が切れていただけ、ということもあった |

## 6. 次の会話で最初にやること

1. この文書と、`gh issue list` で開いている Issue を確認する
2. v0.3（Mac App Store で公開する。docs/plan.md フェーズ10〜12）を進める。Apple Developer Program への登録（個人）はユーザーが行う
3. 決まっていないこと：Bundle ID の新しい名前（本名を含まない、ニックネームなど）、GitHub のユーザー名を変えるか
4. v0.1・v0.2 の振り返り（#32）はまだ
