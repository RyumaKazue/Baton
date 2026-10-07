#!/bin/zsh
# Baton を Release でビルドし、アプリケーションフォルダに入れて起動する。
# 使い方：リポジトリの直下で ./scripts/install-release.sh
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Baton.app"
BUILD_DIR="DerivedData/release"   # DerivedData/ は .gitignore で除外している
BUILT_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME"
INSTALLED_APP="/Applications/$APP_NAME"

echo "==> Release でビルドする"
xcodebuild -project Baton.xcodeproj -scheme BatonMac -destination 'platform=macOS' \
  -configuration Release -derivedDataPath "$BUILD_DIR" -quiet build

echo "==> 動いている Baton を終了する"
# Xcode から起動したものも含めて終了する（同じアプリが2つ動くと、メニューバーのアイコンが2つになるため）
osascript -e 'tell application id "Kazue.Baton" to quit' 2>/dev/null || true
sleep 1

echo "==> $INSTALLED_APP に入れる"
rm -rf "$INSTALLED_APP"
ditto "$BUILT_APP" "$INSTALLED_APP"

echo "==> 起動する"
open "$INSTALLED_APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INSTALLED_APP/Contents/Info.plist")
echo "完了：Baton v$VERSION をインストールしました"
