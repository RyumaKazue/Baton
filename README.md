# Baton

1台の Bluetooth 機器（イヤホンなど）を、複数の Mac・iPhone で切り替えて使うためのアプリです。

これまで「使っていた端末で切断 → 使いたい端末で接続」と2か所で操作していたのを、**使いたい端末で操作するだけ**で済むようにします。

> **v0.1**：この Mac だけで完結する機能（メニューからの接続・切断、スリープ・ロック時の切断と、戻ってきたときの再接続）が使えます。他の端末との切り替えは v0.2 で対応予定です。進み具合は [開発計画](docs/plan.md) を参照してください。

## 主な機能

### v0.1（この Mac だけで完結する機能）

- メニューバーに常駐する（Dock には出ない）。ログイン時に自動で起動できる
- ペアリング済みの音声機器から、Baton で管理する機器を登録する
- 登録した機器を、メニューから接続・切断する。この Mac に接続中かを表示する
- スリープに入るとき・画面をロックしたときに、接続中の機器を切断する
- 戻ってきたとき（ロックを解除したとき）に、離れる前に使っていた機器を再接続する

### 今後の予定

- v0.2：Mac 同士の連携（他の Mac の接続状態の表示、他の Mac に切断を頼んでから接続する切り替え）
- v0.3：iPhone アプリ

## 動作環境

| 項目 | 内容 |
|---|---|
| Mac | macOS 14 以上 |
| iPhone | iOS 17 以上（v0.3 で対応予定） |

## 開発環境

| 項目 | バージョン |
|---|---|
| Xcode | 26.3 |
| Swift | 6.2 |

外部のライブラリは使わず、Apple の標準のフレームワークだけで作っています。

## リポジトリの構成

```
Baton/
├── Baton.xcodeproj           # Xcode のプロジェクト（ターゲット：BatonMac、BatonPhone）
├── BatonMac/                 # Mac アプリ
├── BatonMacTests/            # Mac アプリのテスト
├── BatonPhone/               # iPhone アプリ
├── Packages/BatonKit/        # Mac と iPhone で共通のコード（Swift Package）
│   ├── Sources/BatonKit/
│   └── Tests/BatonKitTests/
├── docs/                     # 仕様書・MVP・開発計画
└── .github/                  # CI、Issue と Pull Request のテンプレート
```

## はじめかた

### 1. clone して開く

```bash
git clone https://github.com/RyumaKazue/Baton.git
```
```bash
open Baton/Baton.xcodeproj
```

### 2. 署名の設定

Xcode で、ターゲット（BatonMac、BatonPhone）の **Signing & Capabilities** を開き、**Team** に自分のチーム（Personal Team で可）を選びます。

## インストール（毎日使う）

Release でビルドしたアプリを、「アプリケーション」フォルダに入れて使います。

```bash
./scripts/install-release.sh
```

スクリプトは、次のことを行います。

1. Release でビルドする
2. 動いている Baton（Xcode から起動したものも含む）を終了する
3. `/Applications/Baton.app` に入れて、起動する

インストールした後に、メニューの「ログイン時に起動」をオンにすると、ログインしたときに自動で起動します。

- 登録した機器は、Xcode から起動した開発中のアプリと共通です（同じ Bundle ID のため）
- 開発中のアプリと、インストールしたアプリを同時に動かさないでください（メニューバーのアイコンが2つになり、両方がスリープ時の処理を行います）
- 新しいバージョンにするときは、もう一度スクリプトを実行します

## ビルド・実行・テスト

### Xcode で行う場合

| 操作 | 手順 |
|---|---|
| ビルド | スキーム `BatonMac`、実行先 `My Mac` を選んで **⌘B** |
| 実行 | **⌘R**（停止は **⌘.**） |
| テスト | スキーム `BatonMac` を選んで **⌘U**（BatonKit と Mac アプリのテストが実行される） |

### ターミナルで行う場合

ビルド：

```bash
xcodebuild -project Baton.xcodeproj -scheme BatonMac -destination 'platform=macOS' build
```

テスト（BatonKit と Mac アプリ）：

```bash
xcodebuild -project Baton.xcodeproj -scheme BatonMac -destination 'platform=macOS' test
```

テスト（BatonKit だけ）：

```bash
swift test --package-path Packages/BatonKit
```

### ダミーの Bluetooth で動かす

スキーム `BatonMac (Mock)` で実行すると、本物の Bluetooth の代わりに、ダミーの機器を使って動きます（イヤホンがなくても画面を確かめられます）。

## ログを見る

Baton は、macOS の統合ログにログを書き込みます（サブシステム `Kazue.Baton`）。

| カテゴリ | 内容 |
|---|---|
| `App` | 起動（本物とダミーのどちらの Bluetooth で動いているか） |
| `Bluetooth` | 接続・切断の開始と結果、Bluetooth の変化の通知 |
| `Devices` | 登録・解除、接続・切断の失敗 |
| `Power` | スリープ・ロック・画面の点灯などの通知 |
| `Sleep` | 離れたときの切断と、戻ってきたときの再接続 |

### Console.app で見る

1. Console.app（コンソール）を開き、左で自分の Mac を選ぶ
2. 右上の検索欄に `subsystem:Kazue.Baton` と入力する
3. 「開始」を押すと、その後のログが流れる

### ターミナルで見る

zsh には `log` という別の組み込みコマンドがあるので、`/usr/bin/log` と書きます。

これから出るログを見る：

```bash
/usr/bin/log stream --predicate 'subsystem == "Kazue.Baton"'
```

過去1時間のログを見る：

```bash
/usr/bin/log show --last 1h --predicate 'subsystem == "Kazue.Baton"'
```

## 開発の進め方

- 作業は Issue ごとにブランチを作り、Pull Request でマージします（`main` は保護されていて、直接 push できません）
- ブランチ名は `feature/<Issue番号>-<内容>`（機能の追加）、`fix/<内容>`（不具合の修正）の形にします
- Pull Request を作ると、CI（GitHub Actions）で BatonKit のテストと、BatonMac のビルド・テストが自動で実行されます。CI が成功しないとマージできません

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [仕様書](docs/spec.md) | アプリ全体の仕様 |
| [MVP](docs/mvp.md) | MVP の範囲 |
| [開発計画](docs/plan.md) | MVP の開発のフェーズと進め方 |
| [開発の状況](docs/status.md) | 今どこにいるか、次にやること、決まっていないこと |
| [受け入れテスト](docs/acceptance-test.md) | v0.1 の受け入れテストのチェックリストと結果 |
| [検証の記録](docs/spikes/) | IOBluetooth、スリープ時の自動接続の検証 |
