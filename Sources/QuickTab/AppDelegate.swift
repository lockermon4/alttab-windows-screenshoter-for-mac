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
        setupStatusItem()
        applyModifier()
        tap.onScreenshot = { ScreenshotController.shared.capture() }
        applyScreenshotHotkey()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            ScreenshotController.shared.screensChanged()
        }
        // Превью включены, а разрешения нет (например, его сбросили) — попросить снова.
        if Previews.shared.enabled { Previews.shared.requestPermission() }

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
        } else {
            // Тап мог не создаться, если права только что выданы — повторим.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
                self?.retryTap()
            }
        }
        rebuildMenu()
    }

    private func retryTap() {
        if tap.start() { started = true; rebuildMenu() }
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
        SkyLight.setSystemCommandTab(enabled: !useCommand)
    }

    private func applyScreenshotHotkey() {
        if ScreenshotSettings.enabled && ScreenshotController.shared.isSupported {
            tap.screenshotHotkey = HotkeyTap.Combo(
                keyCode: Int64(ScreenshotSettings.keyCode),
                flags: CGEventFlags(rawValue: UInt64(ScreenshotSettings.mods.rawValue)))
        } else {
            tap.screenshotHotkey = nil
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
        let status = NSMenuItem(title: started ? "QuickTab работает" : "Нужен «Универсальный доступ»…",
                                action: started ? nil : #selector(openAccessibility), keyEquivalent: "")
        status.target = self
        menu.addItem(status)
        menu.addItem(.separator())

        let opt = NSMenuItem(title: "Сочетание ⌥Tab", action: #selector(useOption), keyEquivalent: "")
        opt.state = useCommand ? .off : .on
        opt.target = self
        menu.addItem(opt)
        let cmd = NSMenuItem(title: "Сочетание ⌘Tab (вместо системного)", action: #selector(useCmd), keyEquivalent: "")
        cmd.state = useCommand ? .on : .off
        cmd.target = self
        menu.addItem(cmd)
        menu.addItem(.separator())

        if Previews.shared.isSupported {
            let prev = NSMenuItem(title: "Показывать превью окон", action: #selector(togglePreviews), keyEquivalent: "")
            prev.state = Previews.shared.enabled ? .on : .off
            prev.target = self
            menu.addItem(prev)
            if Previews.shared.enabled && !Previews.shared.hasPermission {
                let hint = NSMenuItem(title: "   ⚠️ Разрешить «Запись экрана»…", action: #selector(openScreenRecording), keyEquivalent: "")
                hint.target = self
                menu.addItem(hint)
                let restart = NSMenuItem(title: "   Перезапустить QuickTab (после выдачи разрешения)", action: #selector(relaunch), keyEquivalent: "")
                restart.target = self
                menu.addItem(restart)
            }
            menu.addItem(.separator())
        }

        addScreenshotItems(previewHintShown: Previews.shared.enabled && !Previews.shared.hasPermission)

        let login = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Скриншоты

    private func addScreenshotItems(previewHintShown: Bool) {
        let shots = ScreenshotController.shared
        guard shots.isSupported else { return }
        func item(_ title: String, _ action: Selector?) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            menu.addItem(i)
            return i
        }
        let toggle = item("Скриншоты со стоп-кадром", #selector(toggleScreenshots))
        toggle.state = ScreenshotSettings.enabled ? .on : .off
        if ScreenshotSettings.enabled {
            let hk = ScreenshotSettings.hotkeyDescription
            _ = item("   Сделать скриншот   \(hk)", #selector(takeScreenshot))
            _ = item("   Горячая клавиша: \(hk) — изменить…", #selector(changeScreenshotHotkey))

            let after = NSMenuItem(title: "   После выделения", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let modes: [(AfterSelect, String)] = [
                (.copy, "Сразу копировать"),
                (.save, "Копировать и сохранить в папку"),
                (.editor, "Открывать панель рисования"),
            ]
            for (mode, title) in modes {
                let i = NSMenuItem(title: title, action: #selector(setAfterSelect(_:)), keyEquivalent: "")
                i.representedObject = mode.rawValue
                i.state = ScreenshotSettings.after == mode ? .on : .off
                i.target = self
                sub.addItem(i)
            }
            after.submenu = sub
            menu.addItem(after)

            _ = item("   Папка: \(ScreenshotSettings.saveDir.lastPathComponent) — изменить…", #selector(chooseScreenshotFolder))
            _ = item("   Открыть папку со скриншотами", #selector(openScreenshotFolder))
            if !shots.hasPermission && !previewHintShown {
                _ = item("   ⚠️ Разрешить «Запись экрана»…", #selector(openScreenRecording))
                _ = item("   Перезапустить QuickTab (после выдачи разрешения)", #selector(relaunch))
            }
            _ = item("   Сбросить разрешение «Запись экрана»…", #selector(resetScreenRecording))
        }
        menu.addItem(.separator())
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

    @objc private func changeScreenshotHotkey() {
        tap.screenshotHotkey = nil // пока записываем — старое сочетание не срабатывает
        HotkeyRecorder.shared.record { [weak self] result in
            if let r = result {
                ScreenshotSettings.keyCode = r.keyCode
                ScreenshotSettings.mods = r.mods
                ScreenshotSettings.keyName = r.name
                Toast.show("Скриншот: \(ScreenshotSettings.hotkeyDescription)")
            }
            self?.applyScreenshotHotkey()
            self?.rebuildMenu()
        }
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
        panel.prompt = "Выбрать"
        panel.message = "Куда сохранять скриншоты"
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
