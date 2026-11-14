import AppKit

/// Перехват ⌥Tab (или ⌘Tab) через CGEventTap на ОТДЕЛЬНОМ потоке:
/// клавиатура не тормозит, даже если главный поток чем-то занят.
final class HotkeyTap {
    enum Action {
        case begin(reverse: Bool)
        case next, previous, commit, cancel
    }

    var onAction: ((Action) -> Void)?

    /// Модификатор переключателя. Пишется с главного потока, читается в колбэке.
    var modifier: CGEventFlags {
        get { lock.lock(); defer { lock.unlock() }; return _modifier }
        set { lock.lock(); _modifier = newValue; lock.unlock() }
    }

    private var _modifier: CGEventFlags = .maskAlternate
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var active = false // только на потоке тапа

    private enum Key {
        static let tab: Int64 = 48, escape: Int64 = 53, ret: Int64 = 36
        static let left: Int64 = 123, right: Int64 = 124, down: Int64 = 125, up: Int64 = 126
    }

    func start() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap

        let thread = Thread {
            let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "QuickTab.Hotkey"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        let mod = modifier
        let flags = event.flags
        let other: CGEventFlags = mod == .maskCommand ? [.maskControl, .maskAlternate] : [.maskControl, .maskCommand]

        switch type {
        case .flagsChanged:
            if active && !flags.contains(mod) {
                active = false
                send(.commit)
            }
            return pass

        case .keyDown:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            if key == Key.tab && flags.contains(mod) && flags.intersection(other).isEmpty {
                let reverse = flags.contains(.maskShift)
                if active {
                    send(reverse ? .previous : .next)
                } else {
                    active = true
                    send(.begin(reverse: reverse))
                }
                return nil
            }
            guard active else { return pass }
            switch key {
            case Key.escape: active = false; send(.cancel); return nil
            case Key.ret: active = false; send(.commit); return nil
            case Key.left, Key.up: send(.previous); return nil
            case Key.right, Key.down: send(.next); return nil
            default: return pass
            }

        case .keyUp:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            if key == Key.tab && flags.contains(mod) { return nil }
            if active && [Key.escape, Key.ret, Key.left, Key.right, Key.up, Key.down].contains(key) { return nil }
            return pass

        default:
            return pass
        }
    }

    private func send(_ a: Action) {
        DispatchQueue.main.async { [weak self] in self?.onAction?(a) }
    }
}

private func hotkeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                            refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}
