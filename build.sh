#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="行星日报"
SOURCES="$ROOT/app/Sources"
RESOURCES="$ROOT/app/Resources"

# 先构建到项目本地 build 目录，确保沙箱内外均可顺利编译
LOCAL_BUNDLE="$ROOT/build/$APP_NAME.app"
rm -rf "$LOCAL_BUNDLE"
mkdir -p "$LOCAL_BUNDLE/Contents/MacOS" "$LOCAL_BUNDLE/Contents/Resources"

cp "$ROOT/app/Info.plist" "$LOCAL_BUNDLE/Contents/Info.plist"

if [ -f "$RESOURCES/AppIcon.icns" ]; then
    cp "$RESOURCES/AppIcon.icns" "$LOCAL_BUNDLE/Contents/Resources/AppIcon.icns"
fi
if [ -d "$RESOURCES/VoicePreviews" ]; then
    cp -R "$RESOURCES/VoicePreviews" "$LOCAL_BUNDLE/Contents/Resources/VoicePreviews"
fi

swiftc \
    -swift-version 5 \
    -parse-as-library \
    -O \
    -target arm64-apple-macosx14.0 \
    -framework SwiftUI \
    -framework AppKit \
    -framework AVFoundation \
    "$SOURCES/Theme.swift" \
    "$SOURCES/BrandMark.swift" \
    "$SOURCES/Models.swift" \
    "$SOURCES/TTSPlayer.swift" \
    "$SOURCES/DigestStore.swift" \
    "$SOURCES/RefinedLook.swift" \
    "$SOURCES/ContentView.swift" \
    "$SOURCES/ModulesBoard.swift" \
    "$SOURCES/SettingsView.swift" \
    "$SOURCES/DailyDigestApp.swift" \
    -o "$LOCAL_BUNDLE/Contents/MacOS/DailyDigest"

codesign --force --deep --sign - "$LOCAL_BUNDLE" >/dev/null 2>&1

echo "已编译：$LOCAL_BUNDLE"

# CI/preflight can compile without touching the installed application.
if [ "${DAILYDIGEST_BUILD_ONLY:-0}" = "1" ]; then
    exit 0
fi

USER_APP="$HOME/Applications/$APP_NAME.app"
mkdir -p "$HOME/Applications"
STAGE_APP="$HOME/Applications/.$APP_NAME-stage-$$.app"
cp -R "$LOCAL_BUNDLE" "$STAGE_APP"
codesign --verify --deep --strict "$STAGE_APP"
if [ -e "$USER_APP" ]; then
    mv "$USER_APP" "$HOME/Applications/.$APP_NAME-previous.app"
fi
mv "$STAGE_APP" "$USER_APP"
rm -rf "$HOME/Applications/.$APP_NAME-previous.app"
ln -sfn "$USER_APP" "$HOME/Desktop/$APP_NAME.app"
echo "已安装：$USER_APP"
