#!/usr/bin/env bash
# Собирает QuickTab.app в ./build
#   ./scripts/build-app.sh            — только собрать
#   ./scripts/build-app.sh --install  — собрать, положить в /Applications и перезапустить
# Подпись: если есть сертификат «QuickTab Dev» (см. scripts/setup-signing.sh) — используется он,
# иначе ad-hoc. Можно задать явно: SIGN_IDENTITY="Имя" ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0
[ "${1:-}" = "--install" ] && INSTALL=1

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

# Иконка: Resources/AppIcon-1024.png → AppIcon.icns (sips + iconutil есть в любой macOS)
if [ -f Resources/AppIcon-1024.png ]; then
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        d=$((s * 2))
        sips -z $d $d Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

if [ -z "${SIGN_IDENTITY:-}" ] && security find-certificate -c "QuickTab Dev" >/dev/null 2>&1; then
    SIGN_IDENTITY="QuickTab Dev"
fi
codesign --force --sign "${SIGN_IDENTITY:--}" --identifier local.quicktab "$APP"

if [ -z "${SIGN_IDENTITY:-}" ] && [ -z "${CI:-}" ]; then
    # Ad-hoc подпись меняется при каждой сборке: старая запись в «Универсальном доступе»
    # остаётся включённой, но уже не работает. Сбрасываем её, чтобы macOS спросила заново.
    tccutil reset Accessibility local.quicktab >/dev/null 2>&1 || true
    tccutil reset ScreenCapture local.quicktab >/dev/null 2>&1 || true
    echo "⚠️  Подпись ad-hoc — разрешения придётся выдать заново."
    echo "   Чтобы больше так не было, один раз запусти: ./scripts/setup-signing.sh"
fi
echo "Готово: $APP (подпись: ${SIGN_IDENTITY:-ad-hoc})"

if [ "$INSTALL" = 1 ]; then
    pkill -x QuickTab 2>/dev/null || true
    sleep 0.5
    rm -rf /Applications/QuickTab.app
    cp -R "$APP" /Applications/
    open /Applications/QuickTab.app
    echo "Установлено и запущено: /Applications/QuickTab.app"
fi
