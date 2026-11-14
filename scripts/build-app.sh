#!/usr/bin/env bash
# Собирает QuickTab.app в ./build
# SIGN_IDENTITY="QuickTab Dev" ./scripts/build-app.sh  — подписать своим сертификатом
# (тогда разрешение «Универсальный доступ» не слетает после каждой пересборки).
set -euo pipefail
cd "$(dirname "$0")/.."

# Универсальная сборка (arm64 + x86_64) требует полного Xcode.
# С одними Command Line Tools собираем только под текущий Mac.
if [ -z "${ARCHS+x}" ]; then
    if [ -x /Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild ] \
       || xcode-select -p 2>/dev/null | grep -q "Xcode.*\.app"; then
        ARCHS="--arch arm64 --arch x86_64"
    else
        ARCHS=""
    fi
fi
swift build -c release $ARCHS
BIN_DIR=$(swift build -c release $ARCHS --show-bin-path)

APP=build/QuickTab.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/QuickTab" "$APP/Contents/MacOS/QuickTab"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "${SIGN_IDENTITY:--}" --identifier local.quicktab "$APP"
echo "Готово: $APP"
