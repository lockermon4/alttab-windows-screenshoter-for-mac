import AppKit
import ApplicationServices

private final class TrackedApp {
    let pid: pid_t
    let element: AXUIElement
    let name: String
    var observer: AXObserver?
    var windows: [CGWindowID: WindowInfo] = [:]
    var hidden: Bool

    init(app: NSRunningApplication) {
        pid = app.processIdentifier
        element = AXUIElementCreateApplication(pid)
        name = app.localizedName ?? "?"
        hidden = app.isHidden
        AXUIElementSetMessagingTimeout(element, AX.timeout)
    }
}

private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    let pid = pid_t(Int(bitPattern: refcon))
    WindowTracker.shared.handle(notification as String, element: element, pid: pid)
}

/// Держит актуальный список окон в порядке последнего использования (MRU).
/// Всё состояние живёт на AX-потоке; на главный поток уходит только готовый снимок.
final class WindowTracker {
    static let shared = WindowTracker()

    /// Вызывается на главном потоке с новым списком окон.
    var onChange: (([WindowInfo]) -> Void)?

    private let ax = AXThread(name: "QuickTab.AX")
    private let selfPID = ProcessInfo.processInfo.processIdentifier

    // --- состояние AX-потока ---
    private var apps: [pid_t: TrackedApp] = [:]
    private var mru: [CGWindowID] = []
    /// Окно, на которое мы только что переключились. Пока приложение «догоняет»,
    /// запоздалые уведомления о фокусе других окон игнорируются, чтобы порядок
    /// не прыгал при быстром нажатии.
    private var pending: (id: CGWindowID, until: Date)?
    private var publishScheduled = false

    private init() {}

    func start() {
        ax.async { self.bootstrap() }

        let nc = NSWorkspace.shared.notificationCenter
        func on(_ name: Notification.Name, _ body: @escaping (TrackedAppEvent) -> Void) {
            nc.addObserver(forName: name, object: nil, queue: nil) { [weak self] n in
                guard let self,
                      let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else { return }
                self.ax.async { body(TrackedAppEvent(app: app)) }
            }
        }
        on(NSWorkspace.didLaunchApplicationNotification) { self.appLaunched($0.app) }
        on(NSWorkspace.didTerminateApplicationNotification) { self.removeApp($0.app.processIdentifier) }
        on(NSWorkspace.didActivateApplicationNotification) { self.appActivated($0.app) }
        on(NSWorkspace.didHideApplicationNotification) { self.setHidden($0.app, true) }
        on(NSWorkspace.didUnhideApplicationNotification) { self.setHidden($0.app, false) }
    }

    /// Вызывается контроллером сразу при выборе окна (оптимистично).
    func markFocused(_ id: CGWindowID) {
        ax.async {
            self.pending = (id, Date().addingTimeInterval(0.6))
            self.moveToFront(id, force: true)
            self.publish()
        }
    }

    // MARK: - AX-поток

    private struct TrackedAppEvent { let app: NSRunningApplication }

    private func bootstrap() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), AX.timeout)
        for app in NSWorkspace.shared.runningApplications { addApp(app) }

        // Начальный порядок — по z-order окон на экране. Номера окон и PID
        // доступны без разрешения на запись экрана (оно нужно только для заголовков/картинки).
        if let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            let zOrder: [CGWindowID] = info.compactMap { d in
                guard (d[kCGWindowLayer as String] as? Int) == 0 else { return nil }
                return (d[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            }
            let known = Set(mru)
            let front = zOrder.filter { known.contains($0) }
            let frontSet = Set(front)
            mru = front + mru.filter { !frontSet.contains($0) }
        }
        publish()
    }

    private func appLaunched(_ app: NSRunningApplication) {
        // Сразу после запуска приложение может ещё не отвечать на AX — пробуем несколько раз.
        addApp(app)
        for delay in [0.5, 1.5, 4.0] {
            ax.after(delay) { [weak self] in
                guard let self, !app.isTerminated else { return }
                self.addApp(app)
                self.publish()
            }
        }
        publish()
    }

    private func addApp(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular,
              app.processIdentifier != selfPID,
              !app.isTerminated else { return }
        let pid = app.processIdentifier
        let t: TrackedApp
        if let existing = apps[pid] {
            t = existing
        } else {
            t = TrackedApp(app: app)
            apps[pid] = t
        }
        if t.observer == nil { t.observer = makeObserver(for: t) }
        refreshWindows(t)
    }

    private func removeApp(_ pid: pid_t) {
        guard let t = apps.removeValue(forKey: pid) else { return }
        if let obs = t.observer {
            CFRunLoopRemoveSource(ax.runLoop, AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        let ids = Set(t.windows.keys)
        mru.removeAll { ids.contains($0) }
        publish()
    }

    private func appActivated(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        if apps[pid] == nil { addApp(app) }
        guard let t = apps[pid] else { return }
        t.hidden = false
        focusChanged(in: t)
    }

    private func setHidden(_ app: NSRunningApplication, _ hidden: Bool) {
        apps[app.processIdentifier]?.hidden = hidden
        publish()
    }

    private func makeObserver(for t: TrackedApp) -> AXObserver? {
        var observer: AXObserver?
        guard AXObserverCreate(t.pid, axCallback, &observer) == .success, let obs = observer else { return nil }
        let refcon = UnsafeMutableRawPointer(bitPattern: Int(t.pid))
        let result = AXObserverAddNotification(obs, t.element, kAXWindowCreatedNotification as CFString, refcon)
        guard result == .success || result == .notificationAlreadyRegistered else {
            return nil // приложение ещё не готово — попробуем позже
        }
        AXObserverAddNotification(obs, t.element, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(obs, t.element, kAXMainWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(ax.runLoop, AXObserverGetRunLoopSource(obs), .defaultMode)
        return obs
    }

    fileprivate func handle(_ notification: String, element: AXUIElement, pid: pid_t) {
        guard let t = apps[pid] else { return }
        switch notification {
        case kAXWindowCreatedNotification:
            registerWindow(element, in: t)
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            focusChanged(in: t)
            return
        case kAXUIElementDestroyedNotification:
            if let id = t.windows.first(where: { CFEqual($0.value.element, element) })?.key {
                t.windows[id] = nil
                mru.removeAll { $0 == id }
            }
        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            if let id = AX.windowID(element) {
                t.windows[id]?.isMinimized = notification == kAXWindowMiniaturizedNotification
            }
        case kAXTitleChangedNotification:
            if let id = AX.windowID(element), t.windows[id] != nil {
                t.windows[id]?.title = AX.string(element, kAXTitleAttribute) ?? ""
            }
        default:
            return
        }
        publish()
    }

    private func focusChanged(in t: TrackedApp) {
        guard let w = AX.element(t.element, kAXFocusedWindowAttribute), let id = AX.windowID(w) else { return }
        if t.windows[id] == nil { registerWindow(w, in: t) }
        guard t.windows[id] != nil else { return }
        moveToFront(id, force: false)
        publish()
    }

    @discardableResult
    private func registerWindow(_ w: AXUIElement, in t: TrackedApp) -> CGWindowID? {
        guard let id = AX.windowID(w) else { return nil }
        if t.windows[id] != nil {
            t.windows[id]?.title = AX.string(w, kAXTitleAttribute) ?? ""
            t.windows[id]?.isMinimized = AX.bool(w, kAXMinimizedAttribute)
            return id
        }
        guard AX.isSwitchableWindow(w) else { return nil }
        t.windows[id] = WindowInfo(
            id: id, pid: t.pid, element: w, appName: t.name,
            title: AX.string(w, kAXTitleAttribute) ?? "",
            isMinimized: AX.bool(w, kAXMinimizedAttribute)
        )
        if let obs = t.observer {
            let refcon = UnsafeMutableRawPointer(bitPattern: Int(t.pid))
            for n in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                      kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification] {
                AXObserverAddNotification(obs, w, n as CFString, refcon)
            }
        }
        if !mru.contains(id) { mru.append(id) }
        return id
    }

    private func refreshWindows(_ t: TrackedApp) {
        guard let list = AX.elements(t.element, kAXWindowsAttribute) else { return }
        var seen = Set<CGWindowID>()
        for w in list {
            if let id = registerWindow(w, in: t) { seen.insert(id) }
        }
        for id in t.windows.keys where !seen.contains(id) {
            t.windows[id] = nil
            mru.removeAll { $0 == id }
        }
    }

    private func moveToFront(_ id: CGWindowID, force: Bool) {
        if !force, let p = pending, p.until > Date(), p.id != id { return }
        if let i = mru.firstIndex(of: id) { mru.remove(at: i) }
        mru.insert(id, at: 0)
    }

    /// Склеивает пачку уведомлений в одну публикацию.
    private func publish() {
        guard !publishScheduled else { return }
        publishScheduled = true
        ax.async { [weak self] in
            guard let self else { return }
            self.publishScheduled = false
            var byID: [CGWindowID: WindowInfo] = [:]
            for t in self.apps.values {
                for var w in t.windows.values {
                    w.isAppHidden = t.hidden
                    byID[w.id] = w
                }
            }
            var result = self.mru.compactMap { byID.removeValue(forKey: $0) }
            result.append(contentsOf: byID.values)
            DispatchQueue.main.async { self.onChange?(result) }
        }
    }
}
