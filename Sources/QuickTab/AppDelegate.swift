import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        applyModifier()

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

    func applicationWillTerminate(_ notification: Notification) {
        SkyLight.setSystemCommandTab(enabled: true)
    }

    // MARK: - Меню в строке меню

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "QuickTab")
        img?.isTemplate = true
        statusItem.button?.image = img
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
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
                let hint = NSMenuItem(title: "   Разрешить «Запись экрана»…", action: #selector(openScreenRecording), keyEquivalent: "")
                hint.target = self
                menu.addItem(hint)
            }
            menu.addItem(.separator())
        }

        let login = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func useOption() { useCommand = false; rebuildMenu() }
    @objc private func useCmd() { useCommand = true; rebuildMenu() }

    @objc private func togglePreviews() {
        Previews.shared.setEnabled(!Previews.shared.enabled)
        if Previews.shared.enabled { controller.warmUpPreviews() }
        rebuildMenu()
    }

    @objc private func openScreenRecording() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
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
