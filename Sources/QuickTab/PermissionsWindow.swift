import AppKit

/// Окно первичной настройки: разрешения по шагам, вместо пачки системных запросов при запуске.
final class PermissionsWindow: NSObject, NSWindowDelegate {
    static let shared = PermissionsWindow()
    static let doneKey = "onboardingDone"
    /// «Запись экрана» применяется только после перезапуска — сравниваем с состоянием на старте.
    static let screenGrantedAtLaunch = CGPreflightScreenCaptureAccess()

    private var window: NSWindow?
    private var timer: Timer?
    private var screenRequested = false

    private let axStatus = NSTextField(labelWithString: "")
    private let axButton = NSButton()
    private let screenStatus = NSTextField(labelWithString: "")
    private let screenButton = NSButton()
    private let restartButton = NSButton()

    func show() {
        if window == nil { window = makeWindow() }
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        UserDefaults.standard.set(true, forKey: Self.doneKey)
    }

    private func refresh() {
        let ax = AXIsProcessTrusted()
        let screen = CGPreflightScreenCaptureAccess()
        setStatus(axStatus, ax)
        setStatus(screenStatus, screen)
        axButton.isEnabled = !ax
        screenButton.isEnabled = ax && !screen
        // Preflight иногда остаётся false до перезапуска — поэтому кнопка видна и после нажатия «Разрешить».
        restartButton.isHidden = !((screen && !Self.screenGrantedAtLaunch) || screenRequested)
    }

    private func setStatus(_ field: NSTextField, _ granted: Bool) {
        let a = NSMutableAttributedString()
        if granted, let img = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) {
            let att = NSTextAttachment()
            att.image = img.withSymbolConfiguration(.init(paletteColors: [.systemGreen]))
            a.append(NSAttributedString(attachment: att))
            a.append(NSAttributedString(string: " "))
        }
        a.append(NSAttributedString(string: granted ? NSLocalizedString("Granted", comment: "") : NSLocalizedString("Not granted", comment: ""),
                                    attributes: [.foregroundColor: granted ? NSColor.labelColor : NSColor.secondaryLabelColor]))
        field.attributedStringValue = a
    }

    @objc private func openAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        open("Privacy_Accessibility")
    }

    @objc private func grantScreen() {
        Previews.shared.requestPermission()
        screenRequested = true
        open("Privacy_ScreenCapture")
        refresh()
    }

    @objc private func restart() { AppDelegate.relaunch() }
    @objc private func done() { window?.close() }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Вёрстка

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = NSLocalizedString("Set up QuickTab", comment: "")
        w.isReleasedWhenClosed = false
        w.delegate = self

        configure(axButton, NSLocalizedString("Open Settings", comment: ""), #selector(openAccessibility))
        configure(screenButton, NSLocalizedString("Grant", comment: ""), #selector(grantScreen))
        configure(restartButton, NSLocalizedString("Restart QuickTab", comment: ""), #selector(restart))
        let doneButton = NSButton()
        configure(doneButton, NSLocalizedString("Done", comment: ""), #selector(done))
        doneButton.keyEquivalent = "\r"

        let hint = NSTextField(wrappingLabelWithString: NSLocalizedString("If QuickTab isn't in the list, click + and choose QuickTab from Applications.", comment: ""))
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 380

        let steps = NSStackView(views: [
            row(1, NSLocalizedString("Accessibility", comment: ""),
                NSLocalizedString("Needed to switch windows and catch hotkeys.", comment: ""),
                axStatus, [axButton]),
            row(2, NSLocalizedString("Screen Recording", comment: ""),
                NSLocalizedString("Needed for screenshots and window previews.", comment: ""),
                screenStatus, [screenButton, restartButton], extra: hint),
        ])
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 20

        let bottom = NSStackView(views: [NSView(), doneButton])
        bottom.orientation = .horizontal
        let root = NSStackView(views: [steps, bottom])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        bottom.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        root.widthAnchor.constraint(equalToConstant: 460).isActive = true
        w.contentView = root
        return w
    }

    private func configure(_ b: NSButton, _ title: String, _ action: Selector) {
        b.title = title
        b.bezelStyle = .rounded
        b.target = self
        b.action = action
    }

    private func row(_ n: Int, _ title: String, _ detail: String, _ status: NSTextField,
                     _ buttons: [NSButton], extra: NSView? = nil) -> NSView {
        let num = NSTextField(labelWithString: "\(n)")
        num.font = .systemFont(ofSize: 22, weight: .semibold)
        num.textColor = .tertiaryLabelColor
        let t = NSTextField(labelWithString: title)
        t.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let d = NSTextField(wrappingLabelWithString: detail)
        d.textColor = .secondaryLabelColor
        d.preferredMaxLayoutWidth = 380
        let actions = NSStackView(views: [status] + buttons)
        actions.spacing = 12
        let text = NSStackView(views: [t, d, actions] + (extra.map { [$0] } ?? []))
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 6
        let r = NSStackView(views: [num, text])
        r.alignment = .top
        r.spacing = 14
        return r
    }
}
