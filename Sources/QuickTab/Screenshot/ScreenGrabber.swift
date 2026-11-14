import AppKit
import ScreenCaptureKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Снимает все мониторы разом через ScreenCaptureKit.
/// Список мониторов кэшируется, поэтому снимок делается почти мгновенно после нажатия.
@available(macOS 14.0, *)
actor ScreenGrabber {
    static let shared = ScreenGrabber()

    private var displays: [SCDisplay] = []
    private var fetchedAt = Date.distantPast

    func invalidate() {
        fetchedAt = .distantPast
        displays = []
    }

    func captureAll(scales: [CGDirectDisplayID: CGFloat]) async -> [CGDirectDisplayID: CGImage] {
        let known = Set(displays.map(\.displayID))
        if Date().timeIntervalSince(fetchedAt) > 120 || !Set(scales.keys).isSubset(of: known) {
            if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) {
                displays = content.displays
                fetchedAt = Date()
            }
        }
        let targets = displays.filter { scales[$0.displayID] != nil }

        return await withTaskGroup(of: (CGDirectDisplayID, CGImage?).self) { group in
            for display in targets {
                let scale = scales[display.displayID] ?? 2
                group.addTask {
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let cfg = SCStreamConfiguration()
                    cfg.width = Int((CGFloat(display.width) * scale).rounded())
                    cfg.height = Int((CGFloat(display.height) * scale).rounded())
                    cfg.showsCursor = false
                    cfg.captureResolution = .best
                    let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
                    return (display.displayID, img)
                }
            }
            var out: [CGDirectDisplayID: CGImage] = [:]
            for await (id, img) in group {
                if let img { out[id] = img }
            }
            return out
        }
    }
}
