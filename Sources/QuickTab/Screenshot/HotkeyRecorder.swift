import AppKit

/// Окошко «нажми новое сочетание».
final class HotkeyRecorder: NSObject, NSWindowDelegate {
    static let shared = HotkeyRecorder()

    struct Result {
        let keyCode: Int
        let mods: NSEvent.ModifierFlags
        let name: String
    }

    private var panel: NSPanel?
    private var label: NSTextField?
    private var monitor: Any?
    private var completion: ((Result?) -> Void)?

    func record(_ done: @escaping (Result?) -> Void) {
        finish(nil)
        completion = done

        let p = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 360, height: 120),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        p.title = "Горячая клавиша скриншота"
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.delegate = self

        let l = NSTextField(wrappingLabelWithString:
            "Нажми новое сочетание\n(сейчас: \(ScreenshotSettings.hotkeyDescription))\n\nEsc — отмена")
        l.alignment = .center
        l.font = .systemFont(ofSize: 14)
        l.frame = CGRect(x: 20, y: 15, width: 320, height: 90)
        p.contentView?.addSubview(l)
        label = l

        p.center()
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handle(e)
            return nil
        }
    }

    private func handle(_ e: NSEvent) {
        if e.keyCode == 53 { finish(nil); return }
        let mods = e.modifierFlags.intersection(ScreenshotSettings.modMask)
        let isFunction = ScreenshotSettings.functionKeys[e.keyCode] != nil
        if mods.isEmpty && !isFunction {
            label?.stringValue = "Нужен хотя бы один модификатор:\n⌘  ⌥  ⌃  ⇧\n(или клавиша F1–F20)\n\nEsc — отмена"
            return
        }
        if e.keyCode == 48 && (mods == .option || mods == .command || mods == [.option, .shift] || mods == [.command, .shift]) {
            label?.stringValue = "Это сочетание занято переключателем окон.\nПопробуй другое.\n\nEsc — отмена"
            return
        }
        finish(Result(keyCode: Int(e.keyCode), mods: mods, name: ScreenshotSettings.keyName(for: e.keyCode)))
    }

    private func finish(_ r: Result?) {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        let done = completion
        completion = nil
        if let p = panel {
            panel = nil
            p.delegate = nil
            p.close()
        }
        done?(r)
    }

    func windowWillClose(_ notification: Notification) {
        if completion != nil || monitor != nil { finish(nil) }
    }
}
