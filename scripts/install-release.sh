#!/bin/zsh
# アプリ（AutoConnect.app）を Release でビルドし、アプリケーションフォルダに入れて起動する。
# 使い方：リポジトリの直下で ./scripts/install-release.sh
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="AutoConnect.app"
BUILD_DIR="DerivedData/release"   # DerivedData/ は .gitignore で除外している
BUILT_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME"
INSTALLED_APP="/Applications/$APP_NAME"
# 名前を変える前（#70）のアプリ。残っていると、同じアプリが2つ入ってしまう
OLD_INSTALLED_APP="/Applications/Baton.app"

echo "==> Release でビルドする"
xcodebuild -project Baton.xcodeproj -scheme BatonMac -destination 'platform=macOS' \
  -configuration Release -derivedDataPath "$BUILD_DIR" -quiet build

echo "==> 動いているアプリを終了する"
# Xcode から起動したものも含めて終了する（同じアプリが2つ動くと、メニューバーのアイコンが2つになるため）
osascript -e 'tell application id "com.furiel05.AudioAutoConnect" to quit' 2>/dev/null || true
sleep 1

echo "==> $INSTALLED_APP に入れる"
rm -rf "$INSTALLED_APP"
if [[ -d "$OLD_INSTALLED_APP" ]]; then
  echo "    名前を変える前の $OLD_INSTALLED_APP を取り除く"
  rm -rf "$OLD_INSTALLED_APP"
fi
ditto "$BUILT_APP" "$INSTALLED_APP"

echo "==> 起動する"
open "$INSTALLED_APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INSTALLED_APP/Contents/Info.plist")
echo "完了：$APP_NAME（v$VERSION）をインストールしました"
