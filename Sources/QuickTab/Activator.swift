import AppKit
import ApplicationServices

/// Переключение на окно. Выполняется на отдельной очереди, поэтому зависшее
/// приложение не блокирует UI. Каждое новое переключение отменяет недоделанное
/// предыдущее («побеждает последнее»), так что быстрые нажатия не копятся в очередь.
enum Activator {
    private static let queue = DispatchQueue(label: "QuickTab.activate", qos: .userInteractive)
    private static let lock = NSLock()
    private static var generation = 0

    static func activate(_ w: WindowInfo) {
        lock.lock(); generation += 1; let gen = generation; lock.unlock()
        func current() -> Bool { lock.lock(); defer { lock.unlock() }; return gen == generation }

        let app = NSRunningApplication(processIdentifier: w.pid)
        if w.isAppHidden { app?.unhide() }

        queue.async {
            guard current() else { return }
            if w.isMinimized {
                AXUIElementSetAttributeValue(w.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            guard current() else { return }
            // Сначала поднимаем процесс через WindowServer (не зависит от отзывчивости приложения)...
            SkyLight.makeFrontmost(pid: w.pid, windowID: w.id)
            guard current() else { return }
            // ...потом просим само приложение поднять нужное окно.
            AXUIElementSetAttributeValue(w.element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(w.element, kAXRaiseAction as CFString)
        }
        // Контрольный повтор: если приложение проспало первый raise.
        queue.asyncAfter(deadline: .now() + 0.15) {
            guard current() else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier != w.pid else { return }
            SkyLight.makeFrontmost(pid: w.pid, windowID: w.id)
            AXUIElementPerformAction(w.element, kAXRaiseAction as CFString)
        }
    }
}
