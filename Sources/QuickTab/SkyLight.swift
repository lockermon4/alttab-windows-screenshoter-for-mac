import AppKit
import ApplicationServices

// Приватные функции WindowServer (SkyLight). Работают без записи экрана и
// без участия самого приложения — поэтому переключение мгновенное даже
// если целевое приложение подвисло.

@_silgen_name("GetProcessForPID") @discardableResult
private func qt_GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

// SkyLight — приватный фреймворк, его нет в SDK, поэтому грузим функции в рантайме.
private let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

private typealias SetFrontFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
private typealias PostEventFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

private func load<T>(_ name: String, as: T.Type) -> T? {
    guard let skyLight, let sym = dlsym(skyLight, name) else { return nil }
    return unsafeBitCast(sym, to: T.self)
}

private let qt_SLPSSetFrontProcessWithOptions = load("_SLPSSetFrontProcessWithOptions", as: SetFrontFn.self)
private let qt_SLPSPostEventRecordTo = load("SLPSPostEventRecordTo", as: PostEventFn.self)

@_silgen_name("CGSSetSymbolicHotKeyEnabled") @discardableResult
private func qt_CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> CGError

enum SkyLight {
    private static let userGenerated: UInt32 = 0x200

    static func makeFrontmost(pid: pid_t, windowID: CGWindowID) {
        var psn = ProcessSerialNumber()
        if let setFront = qt_SLPSSetFrontProcessWithOptions, qt_GetProcessForPID(pid, &psn) == 0 {
            _ = setFront(&psn, windowID, userGenerated)
            makeKeyWindow(&psn, windowID)
        } else {
            // Запасной путь через публичный AX.
            let appEl = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appEl, AX.timeout)
            AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
    }

    /// Делает окно ключевым синтетическим событием (как это делает WindowServer при клике),
    /// точка клика далеко за пределами окна, так что содержимое не задевается.
    private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID) {
        var bytes = [UInt8](repeating: 0, count: 0x100) // 0xf8 падает на 14.7.4+
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        bytes[0x08] = 0x01
        var id = wid
        withUnsafeBytes(of: &id) { src in
            for i in 0..<4 { bytes[0x3c + i] = src[i] }
        }
        var pt = CGPoint(x: 300_000, y: 300_000)
        withUnsafeBytes(of: &pt) { src in
            for i in 0..<16 { bytes[0x20 + i] = src[i] }
        }
        guard let post = qt_SLPSPostEventRecordTo else { return }
        bytes.withUnsafeMutableBufferPointer { buf in
            _ = post(&psn, buf.baseAddress!)
        }
    }

    /// Включить/выключить системный ⌘Tab (id 1 и 2 = ⌘Tab и ⌘⇧Tab).
    /// Настройка переживает выход из приложения, поэтому при выходе включаем обратно.
    static func setSystemCommandTab(enabled: Bool) {
        qt_CGSSetSymbolicHotKeyEnabled(1, enabled)
        qt_CGSSetSymbolicHotKeyEnabled(2, enabled)
    }
}
