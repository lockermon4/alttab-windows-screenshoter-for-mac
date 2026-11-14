**QuickTab** — a free, open-source window switcher (⌥Tab / ⌘Tab) and frozen-screen screenshot tool for macOS in one menu-bar app.
Бесплатный переключатель окон и скриншотер со стоп-кадром для macOS в одном приложении.

## Features / Возможности
- Window switcher on ⌥Tab, or instead of the system ⌘Tab. Optional window previews.
- The switcher and the screenshotter can each be turned on or off from the menu.
- Screenshots with a frozen screen: `⌘⇧2` area, `⌘⇧1` full screen (both hotkeys configurable).
- Drawing panel: arrows, rectangles, text, marker, pixelate. OCR (`O`), pin on top (`P`), color picker (`C`).
- English and Russian UI.

Not yet: screen recording, scrolling capture.

## Install / Установка
1. Download `QuickTab.zip` below, unzip, move `QuickTab.app` to /Applications.
2. The app is not notarized. Remove the quarantine flag:
   ```bash
   xattr -dr com.apple.quarantine /Applications/QuickTab.app
   ```
   or open it, then System Settings → Privacy & Security → **Open Anyway**.
3. **Accessibility** is required (window switching, hotkeys). **Screen Recording** is optional: without it you get the switcher with app icons and window titles; with it you also get screenshots and window previews. On first launch the **Set up QuickTab** window walks you through both, then **Restart QuickTab**; reopen it via **Permissions…** in the menu. If QuickTab isn't listed in System Settings, add it with **+**.
   Нужны «Универсальный доступ» и «Запись экрана»: при первом запуске их по очереди проведёт окно «Настройка QuickTab» (снова — меню «Разрешения…»).

Если раньше стояла версия с id `local.quicktab`, выдай разрешения заново (id приложения сменился).
Updates keep permissions: all release builds are signed with the same certificate.

Requires macOS 13+, screenshots and previews macOS 14+.
