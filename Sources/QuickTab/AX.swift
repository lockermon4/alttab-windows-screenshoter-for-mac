import AppKit
import ApplicationServices

/// Приватная, но стабильная (с 10.x) функция: AX-окно -> CGWindowID.
/// Не требует записи экрана.
@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AX {
    /// Максимальное время ожидания ответа от приложения. Зависшее приложение
    /// не сможет заблокировать нас дольше этого.
    static let timeout: Float = 0.25

    static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? {
        attr(el, name) as? String
    }

    static func bool(_ el: AXUIElement, _ name: String) -> Bool {
        (attr(el, name) as? Bool) ?? false
    }

    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = attr(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(v, to: AXUIElement.self)
    }

    static func elements(_ el: AXUIElement, _ name: String) -> [AXUIElement]? {
        attr(el, name) as? [AXUIElement]
    }

    static func windowID(_ el: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(el, &id) == .success && id != 0 ? id : nil
    }

    static func isSwitchableWindow(_ el: AXUIElement) -> Bool {
        guard string(el, kAXRoleAttribute) == kAXWindowRole else { return false }
        let sub = string(el, kAXSubroleAttribute)
        return sub == kAXStandardWindowSubrole || sub == kAXDialogSubrole
    }
}
