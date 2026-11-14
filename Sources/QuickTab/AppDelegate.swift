import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let tap = HotkeyTap()
    private let controller = SwitcherController()
    private var statusItem: NSStatusItem!
    private var started = false
    private var permissionTimer: Timer?

    private let useCommandKey = "useCommandTab"
    private var useCommand: Bool {
        get { UserDefaults.standard.bool(forKey: useCommandKey) }
        set { UserDefaults.standard.set(newValue, forKey: useCommandKey); applyModifier() }
    }

    private let switcherKey = "switcherEnabled"
    private var switcherEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: switcherKey) }
        set { UserDefaults.standard.set(newValue, forKey: switcherKey); applyModifier() }
    }

    private var signalSources: [DispatchSourceSignal] = []

    /// Если QuickTab убивают (pkill, Ctrl+C, выход из системы), applicationWillTerminate
    /// не вызывается — и системный ⌘Tab остался бы выключенным. Ловим сигналы сами.
    private func restoreCommandTabOnSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                SkyLight.setSystemCommandTab(enabled: true)
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
        atexit { SkyLight.setSystemCommandTab(enabled: true) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        restoreCommandTabOnSignals()
        ScreenshotSettings.registerDefaults()
        UserDefaults.standard.register(defaults: [switcherKey: true])
        setupStatusItem()
        applyModifier()
        tap.onScreenshot = { ScreenshotController.shared.capture() }
        tap.onFullScreenshot = { ScreenshotController.shared.captureFullScreen() }
        applyScreenshotHotkey()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            ScreenshotController.shared.screensChanged()
        }
        // Превью включены, а разрешения нет (например, его сбросили) — попросить снова.
        // Скриншоты включены по умолчанию — без этого на чистой установке QuickTab даже не попадает в список.
        if Previews.shared.enabled || (ScreenshotSettings.enabled && ScreenshotController.shared.isSupported) {
            Previews.shared.requestPermission()
        }

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) {
            startIfNeeded()
        } else {
            // Ждём, пока пользователь выдаст «Универсальный доступ».
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                if AXIsProcessTrusted() { self?.startIfNeeded() }
            }
        }
    }

    private func startIfNeeded() {
        guard !started else { return }
        permissionTimer?.invalidate()
        permissionTimer = nil

        WindowTracker.shared.onChange = { [weak self] in self?.controller.update($0) }
        WindowTracker.shared.start()
        tap.onAction = { [weak self] in self?.controller.handle($0) }
        if tap.start() {
            started = true
            applyModifier()
        } else {
            // Тап мог не создаться, если права только что выданы — повторим.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
                self?.retryTap()
            }
        }
        rebuildMenu()
    }

    private func retryTap() {
        if tap.start() { started = true; applyModifier(); rebuildMenu() }
        else {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                self?.retryTap()
            }
        }
    }

    private func applyModifier() {
        let m: CGEventFlags = useCommand ? .maskCommand : .maskAlternate
        tap.modifier = m
        controller.modifier = m
        tap.switcherEnabled = switcherEnabled
        // Переключатель выключен — системный ⌘Tab всегда на месте.
        // Пока тап не запущен (нет Accessibility) — тоже; заодно чинит состояние после краша/SIGKILL.
        SkyLight.setSystemCommandTab(enabled: !(started && tap.isRunning && AXIsProcessTrusted() && switcherEnabled && useCommand))
    }

    private func applyScreenshotHotkey() {
        if ScreenshotSettings.enabled && ScreenshotController.shared.isSupported {
            tap.screenshotHotkey = HotkeyTap.Combo(
                keyCode: Int64(ScreenshotSettings.keyCode),
                flags: CGEventFlags(rawValue: UInt64(ScreenshotSettings.mods.rawValue)))
            tap.fullScreenshotHotkey = HotkeyTap.Combo(
                keyCode: Int64(ScreenshotSettings.fullKeyCode),
                flags: CGEventFlags(rawValue: UInt64(ScreenshotSettings.fullMods.rawValue)))
        } else {
            clearScreenshotHotkeys()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SkyLight.setSystemCommandTab(enabled: true)
    }

    // MARK: - Меню в строке меню

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "QuickTab")
        img?.isTemplate = true
        statusItem.button?.image = img
        menu.delegate = self // пункты пересобираются при каждом открытии — состояние всегда свежее
        rebuildMenu()
    }

    private let menu = NSMenu()

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }

    private func rebuildMenu() {
        menu.removeAllItems()
        let status = NSMenuItem(title: started ? NSLocalizedString("QuickTab is running", comment: "") : NSLocalizedString("Accessibility access required…", comment: ""),
                                action: started ? nil : #selector(openAccessibility), keyEquivalent: "")
        status.target = self
        menu.addItem(status)

        // Подсказку про «Запись экрана» показываем один раз: либо у превью, либо у скриншотов.
        let previewHintShown = addSwitcherItems()
        addScreenshotItems(previewHintShown: previewHintShown)

        menu.addItem(.separator())
        let login = item(NSLocalizedString("Launch at login", comment: ""), #selector(toggleLogin), in: menu)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(NSMenuItem(title: NSLocalizedString("Quit QuickTab", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @discardableResult
    private func item(_ title: String, _ action: Selector?, in m: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        m.addItem(i)
        return i
    }

    private func submenu(_ title: String, in m: NSMenu) -> NSMenu {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        parent.submenu = sub
        m.addItem(parent)
        return sub
    }

    private func section(_ title: String) {
        menu.addItem(.separator())
        if #available(macOS 14.0, *) {
            menu.addItem(.sectionHeader(title: title))
        } else {
            let h = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            h.isEnabled = false
            menu.addItem(h)
        }
    }

    /// Показывает сочетание справа, как системный key equivalent; если клавишу так не выразить (F5, стрелки…) — в заголовке.
    private func showHotkey(_ i: NSMenuItem, keyName: String, mods: NSEvent.ModifierFlags, description: String) {
        if keyName.count == 1, let c = keyName.unicodeScalars.first, c.isASCII, c.properties.isGraphemeBase {
            i.keyEquivalent = keyName.lowercased()
            i.keyEquivalentModifierMask = mods.intersection([.command, .option, .control, .shift])
        } else {
            i.title += "   " + description
        }
    }

    /// Возвращает true, если показана подсказка про «Запись экрана».
    private func addSwitcherItems() -> Bool {
        section(NSLocalizedString("Window switcher", comment: ""))
        item(NSLocalizedString("Enabled", comment: ""), #selector(toggleSwitcher), in: menu).state = switcherEnabled ? .on : .off
        guard switcherEnabled else { return false }

        let shortcut = submenu(String(format: NSLocalizedString("Shortcut: %@", comment: ""), useCommand ? "⌘Tab" : "⌥Tab"), in: menu)
        item("⌥Tab", #selector(useOption), in: shortcut).state = useCommand ? .off : .on
        item(NSLocalizedString("⌘Tab (replaces system one)", comment: ""), #selector(useCmd), in: shortcut).state = useCommand ? .on : .off

        guard Previews.shared.isSupported else { return false }
        item(NSLocalizedString("Window previews", comment: ""), #selector(togglePreviews), in: menu).state = Previews.shared.enabled ? .on : .off
        guard Previews.shared.enabled && !Previews.shared.hasPermission else { return false }
        item(NSLocalizedString("Allow Screen Recording…", comment: ""), #selector(openScreenRecording), in: menu)
        item(NSLocalizedString("Restart QuickTab (after granting permission)", comment: ""), #selector(relaunch), in: menu)
        return true
    }

    // MARK: - Скриншоты

    private func addScreenshotItems(previewHintShown: Bool) {
        let shots = ScreenshotController.shared
        guard shots.isSupported else { return }
        section(NSLocalizedString("Screenshots", comment: ""))
        item(NSLocalizedString("Enabled", comment: ""), #selector(toggleScreenshots), in: menu).state = ScreenshotSettings.enabled ? .on : .off
        guard ScreenshotSettings.enabled else { return }

        showHotkey(item(NSLocalizedString("Capture area", comment: ""), #selector(takeScreenshot), in: menu),
                   keyName: ScreenshotSettings.keyName, mods: ScreenshotSettings.mods, description: ScreenshotSettings.hotkeyDescription)
        showHotkey(item(NSLocalizedString("Capture full screen", comment: ""), #selector(takeFullScreenshot), in: menu),
                   keyName: ScreenshotSettings.fullKeyName, mods: ScreenshotSettings.fullMods, description: ScreenshotSettings.fullHotkeyDescription)

        let hotkeys = submenu(NSLocalizedString("Hotkeys", comment: ""), in: menu)
        item(String(format: NSLocalizedString("Area: %@ — change…", comment: ""), ScreenshotSettings.hotkeyDescription), #selector(changeScreenshotHotkey), in: hotkeys)
        item(String(format: NSLocalizedString("Full screen: %@ — change…", comment: ""), ScreenshotSettings.fullHotkeyDescription), #selector(changeFullScreenshotHotkey), in: hotkeys)

        let after = submenu(NSLocalizedString("After capture", comment: ""), in: menu)
        let modes: [(AfterSelect, String)] = [
            (.copy, NSLocalizedString("Copy immediately", comment: "")),
            (.save, NSLocalizedString("Copy and save to folder", comment: "")),
            (.editor, NSLocalizedString("Open drawing panel", comment: "")),
        ]
        for (mode, title) in modes {
            let i = item(title, #selector(setAfterSelect(_:)), in: after)
            i.representedObject = mode.rawValue
            i.state = ScreenshotSettings.after == mode ? .on : .off
        }

        let folder = submenu(NSLocalizedString("Folder", comment: ""), in: menu)
        item(NSLocalizedString("Open folder", comment: ""), #selector(openScreenshotFolder), in: folder)
        item(String(format: NSLocalizedString("Change… (current: %@)", comment: ""), ScreenshotSettings.saveDir.lastPathComponent), #selector(chooseScreenshotFolder), in: folder)

        let rec = submenu(NSLocalizedString("Screen Recording", comment: ""), in: menu)
        if !shots.hasPermission && !previewHintShown {
            item(NSLocalizedString("Allow Screen Recording…", comment: ""), #selector(openScreenRecording), in: rec)
            item(NSLocalizedString("Restart QuickTab (after granting permission)", comment: ""), #selector(relaunch), in: rec)
        }
        item(NSLocalizedString("Reset Screen Recording permission…", comment: ""), #selector(resetScreenRecording), in: rec)
    }

    @objc private func toggleSwitcher() {
        switcherEnabled.toggle()
        if !switcherEnabled { controller.handle(.cancel) } // закрыть открытую панель
        rebuildMenu()
    }

    @objc private func resetScreenRecording() {
        ScreenshotController.shared.resetPermission()
    }

    @objc private func toggleScreenshots() {
        ScreenshotSettings.enabled.toggle()
        if ScreenshotSettings.enabled && !ScreenshotController.shared.hasPermission {
            Previews.shared.requestPermission()
        }
        applyScreenshotHotkey()
        rebuildMenu()
    }

    @objc private func takeScreenshot() {
        // Даём меню закрыться, чтобы оно не попало в кадр.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            ScreenshotController.shared.capture()
        }
    }

    @objc private func takeFullScreenshot() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            ScreenshotController.shared.captureFullScreen()
        }
    }

    @objc private func changeScreenshotHotkey() {
        clearScreenshotHotkeys() // пока записываем — старые сочетания не срабатывают
        HotkeyRecorder.shared.record { [weak self] result in
            if let r = result {
                ScreenshotSettings.keyCode = r.keyCode
                ScreenshotSettings.mods = r.mods
                ScreenshotSettings.keyName = r.name
                Toast.show(String(format: NSLocalizedString("Screenshot: %@", comment: ""), ScreenshotSettings.hotkeyDescription))
            }
            self?.applyScreenshotHotkey()
            self?.rebuildMenu()
        }
    }

    @objc private func changeFullScreenshotHotkey() {
        clearScreenshotHotkeys()
        HotkeyRecorder.shared.record(title: NSLocalizedString("Full-screen screenshot hotkey", comment: ""),
                                     current: ScreenshotSettings.fullHotkeyDescription) { [weak self] result in
            if let r = result {
                ScreenshotSettings.fullKeyCode = r.keyCode
                ScreenshotSettings.fullMods = r.mods
                ScreenshotSettings.fullKeyName = r.name
                Toast.show(String(format: NSLocalizedString("Full-screen screenshot: %@", comment: ""), ScreenshotSettings.fullHotkeyDescription))
            }
            self?.applyScreenshotHotkey()
            self?.rebuildMenu()
        }
    }

    private func clearScreenshotHotkeys() {
        tap.screenshotHotkey = nil
        tap.fullScreenshotHotkey = nil
    }

    @objc private func setAfterSelect(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = AfterSelect(rawValue: raw) {
            ScreenshotSettings.after = mode
        }
        rebuildMenu()
    }

    @objc private func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("Choose", comment: "")
        panel.message = NSLocalizedString("Where to save screenshots", comment: "")
        panel.directoryURL = ScreenshotSettings.saveDir
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            ScreenshotSettings.saveDir = url
        }
        rebuildMenu()
    }

    @objc private func openScreenshotFolder() {
        let dir = ScreenshotSettings.saveDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func useOption() { useCommand = false; rebuildMenu() }
    @objc private func useCmd() { useCommand = true; rebuildMenu() }

    @objc private func togglePreviews() {
        Previews.shared.setEnabled(!Previews.shared.enabled)
        if Previews.shared.enabled { controller.warmUpPreviews() }
        rebuildMenu()
    }

    @objc private func openScreenRecording() {
        Previews.shared.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("QuickTab: login item error: \(error)")
        }
        rebuildMenu()
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
