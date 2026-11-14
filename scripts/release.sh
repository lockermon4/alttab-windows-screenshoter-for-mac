#!/usr/bin/env bash
# Собирает QuickTab.app и упаковывает в build/QuickTab-<версия>.zip (+ .dmg) для GitHub Releases.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
# Релиз только с постоянной подписью, иначе у пользователей слетят разрешения после обновления.
security find-certificate -c "QuickTab Dev" >/dev/null 2>&1 || { echo "Нет сертификата «QuickTab Dev»: сначала ./scripts/setup-signing.sh" >&2; exit 1; }
SIGN_IDENTITY="QuickTab Dev" ./scripts/build-app.sh

ZIP="build/QuickTab-${VERSION}.zip"
DMG="build/QuickTab-${VERSION}.dmg"
rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent build/QuickTab.app "$ZIP"

# Отдельная временная папка: hdiutil не спотыкается о смонтированный том «QuickTab» или старые файлы.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto build/QuickTab.app "$STAGE/QuickTab.app"
ln -s /Applications "$STAGE/Applications"
hdiutil detach "/Volumes/QuickTab" -quiet 2>/dev/null || true
hdiutil create -volname QuickTab -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "Готово: $ZIP, $DMG"
echo "Публикация: git tag v${VERSION} && git push origin v${VERSION}, затем создай релиз на GitHub и приложи оба файла."
