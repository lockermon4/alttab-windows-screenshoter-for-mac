**QuickTab** — a free, open-source window switcher (⌥Tab / ⌘Tab) and frozen-screen screenshot tool for macOS in one menu-bar app.
Бесплатный переключатель окон и скриншотер со стоп-кадром для macOS в одном приложении.

## Features / Возможности
- Window switcher on ⌥Tab, or instead of the system ⌘Tab. Needs only Accessibility; window previews are optional.
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
3. Grant **Accessibility**. For screenshots and previews also grant **Screen Recording** (if QuickTab isn't listed, add it with **+**), then restart QuickTab from its menu.

Если раньше стояла версия с id `local.quicktab`, выдай разрешения заново (id приложения сменился).
Updates keep permissions: all release builds are signed with the same certificate.

Requires macOS 13+, screenshots and previews macOS 14+.
