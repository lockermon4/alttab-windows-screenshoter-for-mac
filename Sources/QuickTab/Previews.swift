import AppKit
import ScreenCaptureKit

/// Миниатюры окон. Включаются галочкой в меню и требуют разрешения
/// «Запись экрана» — без него macOS не отдаёт картинку чужих окон.
/// Снимки делаются в фоне и кэшируются: панель никогда их не ждёт.
final class Previews {
    static let shared = Previews()

    /// Вызывается на главном потоке, когда пришёл свежий снимок.
    var onUpdate: ((CGWindowID, NSImage) -> Void)?

    /// Максимальная сторона миниатюры в точках.
    static let maxSide: CGFloat = 210

    private let key = "showPreviews"
    private var cache: [CGWindowID: NSImage] = [:]
    private var inFlight = Set<CGWindowID>()
    private var capturedAt: [CGWindowID: Date] = [:]

    var isSupported: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    var enabled: Bool {
        isSupported && UserDefaults.standard.bool(forKey: key)
    }

    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Запросить «Запись экрана». Заодно делает пробный запрос к ScreenCaptureKit —
    /// именно он гарантированно добавляет QuickTab в список в Настройках
    /// (одного CGRequestScreenCaptureAccess после сброса разрешений бывает мало).
    func requestPermission() {
        guard !hasPermission else { return }
        CGRequestScreenCaptureAccess()
        if #available(macOS 14.0, *) {
            Task.detached {
                _ = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            }
        }
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: key)
        if on {
            requestPermission()
        } else {
            cache.removeAll()
            capturedAt.removeAll()
        }
    }

    func image(for id: CGWindowID) -> NSImage? { cache[id] }

    /// Обновить снимки указанных окон (главный поток). Возвращается сразу.
    func refresh(_ windows: [WindowInfo]) {
        guard enabled, hasPermission else { return }
        let now = Date()
        let ids = windows
            .filter { !$0.isMinimized && !$0.isAppHidden } // свёрнутые снять нельзя — оставляем последний снимок
            .map(\.id)
            .filter { !inFlight.contains($0) && now.timeIntervalSince(capturedAt[$0] ?? .distantPast) > 0.5 }
        guard !ids.isEmpty else { return }
        ids.forEach { inFlight.insert($0) }

        if #available(macOS 14.0, *) {
            Task.detached(priority: .userInitiated) {
                await Capturer.shared.capture(ids, maxSide: Previews.maxSide) { id, cg in
                    DispatchQueue.main.async { self.store(id, cg) }
                }
                DispatchQueue.main.async { ids.forEach { self.inFlight.remove($0) } }
            }
        }
    }

    /// Убрать снимки закрытых окон.
    func prune(keeping ids: Set<CGWindowID>) {
        for id in cache.keys where !ids.contains(id) {
            cache[id] = nil
            capturedAt[id] = nil
        }
    }

    private func store(_ id: CGWindowID, _ cg: CGImage) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
        cache[id] = img
        capturedAt[id] = Date()
        onUpdate?(id, img)
    }
}

@available(macOS 14.0, *)
private actor Capturer {
    static let shared = Capturer()

    private var windows: [CGWindowID: SCWindow] = [:]
    private var fetchedAt = Date.distantPast

    func capture(_ ids: [CGWindowID], maxSide: CGFloat,
                 deliver: @escaping @Sendable (CGWindowID, CGImage) -> Void) async {
        // Список окон ScreenCaptureKit дорогой — обновляем не чаще раза в 0.3–1.5 с.
        let age = Date().timeIntervalSince(fetchedAt)
        let missing = ids.contains { windows[$0] == nil }
        if age > 1.5 || (missing && age > 0.3) {
            if let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) {
                windows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
                fetchedAt = Date()
            }
        }

        let targets = ids.compactMap { windows[$0] }
        await withTaskGroup(of: Void.self) { group in
            for w in targets {
                group.addTask {
                    let frame = w.frame
                    guard frame.width > 1, frame.height > 1 else { return }
                    let scale = min(1, maxSide / max(frame.width, frame.height)) * 2 // ×2 для Retina
                    let cfg = SCStreamConfiguration()
                    cfg.width = max(1, Int(frame.width * scale))
                    cfg.height = max(1, Int(frame.height * scale))
                    cfg.showsCursor = false
                    cfg.ignoreShadowsSingleWindow = true
                    let filter = SCContentFilter(desktopIndependentWindow: w)
                    if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) {
                        deliver(w.windowID, img)
                    }
                }
            }
        }
    }
}
