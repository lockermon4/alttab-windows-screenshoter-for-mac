import AppKit

struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let element: AXUIElement
    let appName: String
    var title: String
    var isMinimized: Bool
    var isAppHidden: Bool = false

    var displayTitle: String { title.isEmpty ? appName : title }
}
