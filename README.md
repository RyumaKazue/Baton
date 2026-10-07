# Baton

1台の Bluetooth 機器（イヤホンなど）を、複数の Mac・iPhone で切り替えて使うためのアプリです。

これまで「使っていた端末で切断 → 使いたい端末で接続」と2か所で操作していたのを、**使いたい端末で操作するだけ**で済むようにします。

> **開発中**：現在は MVP（v0.1：Mac 同士の切り替え）を開発しています。進み具合は [開発計画](docs/plan.md) を参照してください。

## 主な機能（MVP）

- メニューバーに常駐する Mac アプリ
- 登録した Bluetooth 機器が、どの Mac に接続中か（だったか）を表示する
- 操作した Mac に機器を切り替える（接続中の Mac に切断を依頼してから接続する）
- スリープに入るときに機器を切断し、復帰したときに再接続する

iPhone アプリ（Mac から iPhone への切り替え）は、MVP の後に開発します。

## 動作環境

| 項目 | 内容 |
|---|---|
| Mac | macOS 14 以上 |
| iPhone | iOS 17 以上（MVP の後に対応） |
| ネットワーク | すべての端末が同じ LAN（Wi-Fi）に接続していること |

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
