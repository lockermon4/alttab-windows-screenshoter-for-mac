[Русский](README.ru.md) · **English**

# QuickTab

<img src="Resources/AppIcon-1024.png" width="128" alt="">

**Windows-style Alt+Tab plus a Lightshot-style screenshot tool for macOS.**

A lightweight macOS menu-bar app that switches windows the way Windows Alt+Tab does.

**Features:** window switcher on `⌥Tab` / `⌘Tab` · optional window previews · freeze-frame screenshots · drawing on top of a screenshot · text recognition (OCR) · pinning a screenshot above other windows · color picker.
The switcher and the screenshot tool are turned on and off **independently** from the menu-bar icon, so you can use just one of them.

[**Download the latest version**](https://github.com/lockermon4/alttab-windows-screenshoter-for-mac/releases/latest) · [How to install](#install)

- **Two ways to run it**, depending on the permissions you grant:

  | | Accessibility only | Accessibility + Screen Recording |
  |---|---|---|
  | Window switcher (`⌥Tab` / `⌘Tab`) | yes, with app icons and window titles | yes |
  | Window previews in the switcher | no | yes (optional, macOS 14+) |
  | Screenshots: area, full screen, drawing, OCR, pin | no | yes (macOS 14+) |

  Accessibility is always required. Screen Recording is optional: if you only want the switcher, skip that step in the setup window. You can grant it later via **Permissions…**.
- **Doesn't hang when you press it rapidly.**
  - The window list is always cached and ready.
  - The keyboard is handled on its own thread.
  - All calls to other apps run in the background with a 0.25 s timeout.
  - Windows are raised through WindowServer.
  - Each new press cancels the unfinished previous one, so a frozen app doesn't slow the switcher down.
- A quick `⌥Tab` switches straight to the previous window without even drawing the panel.
- **Window previews are optional** (menu checkbox, off by default, macOS 14+). They need Screen Recording. Thumbnails are captured in the background and cached, so they don't slow the switcher down.
- **Built-in freeze-frame screenshots** (like Lightshot/Shottr, macOS 14+). Press the hotkey (default `⌘⇧2`, changeable in the menu), the screen freezes at that moment, select an area and it's already on the clipboard. Needs Screen Recording. Can be turned off in the menu.

## Controls

| Keys | Action |
|---|---|
| `⌥Tab` (hold `⌥`) | open / next window |
| `⌥⇧Tab`, `←` `↑` | previous window |
| `→` `↓` | next window |
| release `⌥`, `Return`, mouse click | switch |
| `Esc` | cancel |

From the menu (menu-bar icon) you can:
- turn the window switcher on or off (**Window switcher → Enabled**; screenshots keep working);
- change the shortcut to `⌘Tab` (**Shortcut → ⌘Tab (replaces system one)**). The system ⌘Tab is disabled while QuickTab runs and comes back when QuickTab exits: via **Quit QuickTab**, `pkill`, Ctrl+C in Terminal, or logging out. If QuickTab crashed and the system ⌘Tab doesn't work, start QuickTab and quit it from the menu, or switch the shortcut back to **⌥Tab**; as a last resort, log out and back in;
- turn on **Window previews** (asks for Screen Recording; restart QuickTab after granting it);
- turn on **Launch at login**.

## Screenshots

Press the hotkey (default `⌘⇧2`): the screen freezes, select an area with the mouse, and the image lands on the clipboard. Requires macOS 14+.

In the menu, under **Screenshots**:
- **Enabled** — turn the feature on or off;
- **Capture area** — same as the hotkey;
- **Capture full screen** — capture the whole screen (default `⌘⇧1`);
- **Hotkeys → Area: … — change…** / **Full screen: … — change…** — a window opens, press the new combination (`Esc` cancels);
- **After capture**: **Copy immediately** (default) / **Copy and save to folder** / **Open drawing panel**;
- **Folder → Change…** — where to save (default `~/Pictures/QuickTab Screenshots`);
- **Folder → Open folder**.

Tip: hold `⌥` while releasing the mouse to open the drawing panel even in **Copy immediately** mode.

| Keys (on the frozen frame) | Action |
|---|---|
| drag | select an area (drag the handles to resize, drag inside to move) |
| `↩`, `⌘C`, double-click | copy and close |
| `⌘S` | save to folder (and copy) |
| `P` | pin above other windows (draggable, scroll wheel zooms, double-click / `Esc` closes, right-click opens a menu) |
| `O` | recognize text (OCR, Russian + English) and copy it |
| `C` | copy the HEX color under the cursor (magnifier) |
| `⌘Z` | undo |
| `⌘A` | select the whole screen |
| `V` `B` `L` `A` `R` `E` `M` `T` `X` | select, pencil, line, arrow, rectangle, ellipse, marker, text, pixelate |
| `⇧` while drawing | square / circle, lines at 45° |
| arrows (`⇧` + arrows) | move the cursor by 1 (10) px |
| right-click | clear the selection, again to close |
| `Esc` | close |

On first use macOS asks for Screen Recording. After granting it, restart QuickTab (menu item **Restart QuickTab (after granting permission)**).

### Asks for Screen Recording although it's on
macOS ties the permission to the app's signature. If you install a build with a different signature (old ad-hoc builds from Actions, a build made without `./scripts/setup-signing.sh`, or switching between your own build and a release build), the checkbox in System Settings stays on but no longer works.

- **From the app.** When a screenshot fails, QuickTab shows a dialog with a **Reset and allow again** button. It removes the old entry, requests the permission again and opens System Settings. Turn QuickTab on there and it restarts by itself. The same action is in the menu: **Screenshots → Screen Recording → Reset Screen Recording permission…**.
- **Manually.** Run the command below, then turn QuickTab on again in System Settings and restart it:
  ```bash
  tccutil reset ScreenCapture io.github.lockermon4.quicktab
  ```
- **To stop it from happening again**, run `./scripts/setup-signing.sh` once and build with `./scripts/build-app.sh --install` (see [Keeping permissions across rebuilds](#keeping-permissions-across-rebuilds)).

## Install

Requires macOS 13+ (window previews and screenshots need macOS 14+).

### Option 1: release build
1. Download `QuickTab.zip` from [**Releases**](https://github.com/lockermon4/alttab-windows-screenshoter-for-mac/releases/latest) and unzip it (double-click).
2. Drag `QuickTab.app` into **Applications** (`/Applications`).
3. **First launch.** The app isn't notarized by Apple (no paid Developer ID), so macOS blocks it at first ("cannot verify the developer"). Any of these gets around it:
   - right-click `QuickTab.app` → **Open** → **Open**;
   - or, if there's no such button (macOS 15+): try to open it, then go to **System Settings → Privacy & Security**, find "QuickTab was blocked" at the bottom and click **Open Anyway**;
   - or run one command in Terminal:
     ```bash
     xattr -dr com.apple.quarantine /Applications/QuickTab.app
     ```
4. **Permissions.** **Accessibility** is required (window switching, hotkeys); **Screen Recording** is optional (screenshots, window previews; see the "Two ways to run it" table above). On first launch the **Set up QuickTab** window walks you through them one at a time: Accessibility first, then Screen Recording, then **Restart QuickTab**. You can reopen it from the menu: **Permissions…**.
   If QuickTab isn't in a list in System Settings, click **+** below the list and choose `/Applications/QuickTab.app`. If AltTab or another switcher also uses ⌥Tab, quit it.

**Updating:** download the new `QuickTab.zip` and replace the app in Applications. Permissions are kept, because all release builds are signed with the same certificate. If macOS still asks for permissions again, see [Asks for Screen Recording although it's on](#asks-for-screen-recording-although-its-on).

### Option 2: build from source
You need Xcode or the Command Line Tools (`xcode-select --install`).
```bash
git clone https://github.com/lockermon4/alttab-windows-screenshoter-for-mac.git QuickTab && cd QuickTab
./scripts/setup-signing.sh      # once: a personal certificate so permissions survive rebuilds
./scripts/build-app.sh --install
```

### Keeping permissions across rebuilds
By default the app is signed ad-hoc, and the signature changes with every build. macOS ties permissions to the signature, so the old Accessibility entry stays enabled but no longer works.

To avoid this, create a personal certificate **once** (macOS will ask for your password):
```bash
./scripts/setup-signing.sh
```
After that, build and install with one command and permissions are kept:
```bash
./scripts/build-app.sh --install
```

If permissions are already broken, reset them and grant them again:
```bash
tccutil reset Accessibility io.github.lockermon4.quicktab; tccutil reset ScreenCapture io.github.lockermon4.quicktab
```

### Signing GitHub builds (for the repository owner)
GitHub Actions signs every build with one permanent "QuickTab Dev" certificate from the repository secrets, so macOS doesn't reset Accessibility and Screen Recording on update. Without the secrets the build is signed ad-hoc.

To set it up, run this **once** on your Mac:
```bash
./scripts/setup-ci-signing.sh
```
The script:
- creates a new "QuickTab Dev" certificate (replacing the old local one), installs it and marks it as trusted;
- keeps a copy in `~/.quicktab-signing/`;
- uploads the `QUICKTAB_P12_BASE64` and `QUICKTAB_P12_PASSWORD` secrets to the repository via `gh`. This needs `gh auth login`. Without `gh` the script prints what to add by hand: **Settings → Secrets and variables → Actions → New repository secret**.

After that, local builds and GitHub builds are signed the same way. Rebuild the app and grant the permissions once more (the certificate changed):
```bash
./scripts/build-app.sh --install
```

To publish a release, push a `v*` tag; Actions builds `QuickTab.zip` and uploads it to Releases.
```bash
git tag v1.2.0 && git push origin v1.2.0
```

## How it works

| File | What it does |
|---|---|
| `WindowTracker.swift` | Window list in most-recently-used order. AXObservers on a separate thread; initial order from the `CGWindowList` z-order (no Screen Recording needed). |
| `HotkeyTap.swift` | CGEventTap on its own thread. Also catches the screenshot hotkey. |
| `Activator.swift`, `SkyLight.swift` | Switching to a window: background queue, "last press wins". |
| `SwitcherPanel.swift` | The panel (NSPanel that doesn't take focus). |
| `Previews.swift` | Optional thumbnails via ScreenCaptureKit, in the background with a cache. |
| `Screenshot/ScreenshotController.swift` | Screenshots: orchestration, clipboard, saving, OCR via Vision. |
| `Screenshot/ScreenGrabber.swift` | Captures all displays via ScreenCaptureKit; the display list is cached, so the freeze frame is instant. |
| `Screenshot/ScreenshotOverlay.swift` | Freeze-frame window: selection, drawing tools, magnifier, toolbar. |
| `Screenshot/PinWindow.swift` | A screenshot pinned above other windows. |
| `Screenshot/HotkeyRecorder.swift` | Window for recording a new hotkey. |
| `Screenshot/ScreenshotSettings.swift` | Screenshot settings. |

Requires macOS 13+ (window previews and screenshots need macOS 14+).

## Releasing (for the author)

GitHub Actions builds the release from a tag and signs it with the permanent "QuickTab Dev" certificate from the repository secrets (one-time setup: `./scripts/setup-ci-signing.sh`, see above). That way users keep their permissions after updating.

1. Bump `CFBundleShortVersionString` / `CFBundleVersion` in `Resources/Info.plist` and update `.github/release-notes.md`.
2. `git tag v<version> && git push origin v<version>` — CI builds `QuickTab.zip` and publishes the release.

`./scripts/release.sh` builds the same thing locally (zip + dmg in `build/`).

## License

MIT — see [LICENSE](LICENSE).
