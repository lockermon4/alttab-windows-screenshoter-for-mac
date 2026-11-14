#!/usr/bin/env bash
# Собирает QuickTab.app в ./build
# SIGN_IDENTITY="QuickTab Dev" ./scripts/build-app.sh  — подписать своим сертификатом
# (тогда разрешение «Универсальный доступ» не слетает после каждой пересборки).
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=${ARCHS:-"--arch arm64 --arch x86_64"}
swift build -c release $ARCHS
BIN_DIR=$(swift build -c release $ARCHS --show-bin-path)

APP=build/QuickTab.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/QuickTab" "$APP/Contents/MacOS/QuickTab"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "${SIGN_IDENTITY:--}" --identifier local.quicktab "$APP"
echo "Готово: $APP"
