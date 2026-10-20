# 調査：Mac App Store の審査に通るか

調査日：2026-10-20
Issue：#65

## 1. 目的

Baton を Mac App Store に出すにあたって、審査（App Review）で問題になりそうな点を調べ、直すかどうかを決める。

## 2. 結論

| 点 | 結論 | 対応 |
|---|---|---|
| 公開の API だけを使っているか（2.5.1） | アプリが呼んでいる関数・クラスは、すべて公開のもの。ただし、**公開されていない名前（文字列）を3つ使っている**（ロックの通知の名前2つ、ロック中かの値の名前1つ） | 3つの扱いを決める（→ 4.1） |
| 自分で起動し直す（#51） | 審査の決まりに、はっきり禁じる項目はない。近いのは 2.4.5(iii)「ユーザーが終了した後も動き続けるプロセスを起こさない」だが、Baton はユーザーが終了していないときに、自分自身を入れ替えるだけ | そのまま。審査の担当者向けの説明に、理由を書く |
| プライバシーマニフェスト（`PrivacyInfo.xcprivacy`） | Apple の説明で、必須とされているのは iOS・iPadOS・tvOS・visionOS・watchOS。macOS は書かれていない | 必須ではないが、入れておく（UserDefaults の理由 `CA92.1`）。害はない |
| Mac App Store のアプリの決まり（2.4.5 の i〜ix） | すべて満たしている（→ 4.3） | なし |

## 3. 確かめ方

- App Review Guidelines（Apple の公式のページ）の 2.4.5 と 2.5.1 を読んだ
- Apple の「Describing use of required reason API」の本文（ドキュメントの JSON）を読んだ
- `/Applications` に入れた Release 版の Baton（v0.2）で、`nm -u` で使っている関数・クラスの一覧を、`strings` で中に含まれる文字列を調べた
- 開発者の掲示板や、ほかの開発者の記事を検索した

## 4. 結果の詳細

### 4.1 公開の API だけを使っているか（2.5.1）

Guideline 2.5.1 は「公開の API だけを使うこと」を求めている。Apple Developer Program License Agreement も、Mac App Store に出すアプリは「文書化された API」だけを使うよう求めている。

`nm -u` で見た、アプリが使っている関数・クラスは、すべて公開のものだった（CoreAudio の `AudioObjectGetPropertyData` など、CoreGraphics の `CGSessionCopyCurrentDictionary`、`CGDisplayIsAsleep`、`IOBluetoothDevice`、`CBCentralManager`、`NSWorkspace`、`NSDistributedNotificationCenter`、`SMAppService` など）。

一方、公開の API に渡している**名前（文字列）**のうち、次の3つは Apple が文書にしていない。

| 文字列 | 使っている場所 | 何に使っているか |
|---|---|---|
| `com.apple.screenIsLocked` | `NSWorkspacePowerEventService` | 画面がロックされたことを知る（`DistributedNotificationCenter` で受け取る通知の名前） |
| `com.apple.screenIsUnlocked` | 同上 | ロックが解除されたことを知る |
| `CGSSessionScreenIsLocked` | 同上 | 今ロック中かを確かめる（`CGSessionCopyCurrentDictionary` が返す辞書のキー） |

- 関数やクラスは公開のものなので、審査の機械的な検査（非公開の関数・クラスの検出）には引っかかりにくいと考えられる。ただ、文字列まで調べられるかは分からない
- 審査に通った・断られた、という具体的な例は見つからなかった
- ロックとロック解除を知る**公開の**方法は、見つからなかった。公開の通知でいちばん近いのは「画面が消えた」「画面が点いた」（`screensDidSleepNotification` / `screensDidWakeNotification`）だが、ロック画面のままなのか、ロックが解除されたのかは区別できない

**対応の案**

| 案 | 内容 | 良い点 | 気になる点 |
|---|---|---|---|
| A. そのまま出す | 3つの文字列を使ったまま出す。断られたら B にする | 今の動きのまま。断られる可能性は低いと考えられる | 断られると、直して出し直す手間がかかる（数日） |
| B. 公開のものだけにする | ロックの代わりに「画面が消えた」で切断し、「画面が点いた」で再接続する | 審査の心配がない | ロック画面のまま（解除の前）に再接続してしまう。フェーズ4で避けた動き（[sleep-reconnect.md](sleep-reconnect.md) 5）に戻る |

### 4.2 自分で起動し直す（#51）

- 審査の決まりに、アプリが自分を起動し直すことを、はっきり禁じる項目はなかった
- 近いのは 2.4.5(iii)：ログイン時などに同意なく起動しないこと、ユーザーが終了した後も動き続けるプロセスを起こさないこと
- Baton は、ユーザーが終了していないときに、壊れた状態から直すために自分自身を入れ替えるだけで、終了した後に動き続けるものはない
- 審査の担当者向けの説明に、「macOS の Bluetooth の仕組みが起動し直したとき（電池切れの深いスリープから起きたときなど）、Bluetooth の情報を作り直すために、アプリが自分を起動し直す」と書く

### 4.3 Mac App Store のアプリの決まり（2.4.5）

| 項目 | 決まり | Baton |
|---|---|---|
| (i) | Sandbox に入っていること | ✅ Sandbox は ON |
| (ii) | Xcode で作って出すこと。1つのアプリの中に収まっていること | ✅ |
| (iii) | 同意なくログイン時に起動しないこと。終了後に動き続けるプロセスを起こさないこと。Dock にアイコンを勝手に足さないこと | ✅ ログイン時に起動は、ユーザーが設定でオンにしたときだけ（初期値オフ）。Dock には出ない |
| (iv) | 機能を足すためのコードをダウンロードしないこと | ✅ |
| (v) | 管理者の権限を求めないこと | ✅ |
| (vi) | 起動時にライセンスの画面を出さないこと | ✅ |
| (vii) | 更新は Mac App Store で配ること | ✅ 自分で更新する仕組みはない（`install-release.sh` は開発用） |
| (viii) | 今の macOS で動き、廃止された技術を使わないこと | ✅ ビルドで、廃止された API の警告は出ていない |
| (ix) | 言語の対応を、1つのアプリの中に入れること | ✅ 英語の対応も String Catalog でアプリの中に入れる（#66） |

### 4.4 プライバシーマニフェスト

Apple の「Describing use of required reason API」の本文では、required reason API の理由を書くことが求められているのは「iOS、iPadOS、tvOS、visionOS、watchOS」のアプリと SDK で、macOS は挙げられていない。2024年5月1日から、理由が書かれていないアプリは App Store Connect で受け付けられなくなった（これらの OS について）。

Baton は UserDefaults（登録機器と設定の保存）を使っている。UserDefaults は required reason API の1つで、アプリだけが読み書きする場合の理由は `CA92.1`。macOS では必須ではないが、将来 macOS も対象になったときのために、入れておく。

## 5. 決めたこと（2026-10-20）

| 項目 | 決定 |
|---|---|
| 4.1 の3つの文字列 | **A：そのまま出す**。審査で断られたら、B（公開のものだけにする）に変える |
| 自分で起動し直す | そのまま。審査の担当者向けの説明に理由を書く（#67） |
| プライバシーマニフェスト | 入れる（`BatonMac/Resources/PrivacyInfo.xcprivacy`。UserDefaults、`CA92.1`） |

## 6. 参考

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)（2.4.5、2.5.1）
- [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement)
- [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [AppStore rejected: use of private …（Apple Developer Forums）](https://developer.apple.com/forums/thread/63257)
- [Automatically restarting a Mac App Store sandboxed app（Apple Developer Forums）](https://developer.apple.com/forums/thread/706112)
- [Building a macOS Locked Status Notifier in Swift](https://www.raygesualdo.com/posts/building-a-macos-locked-status-notifier-in-swift/)
