import AppKit

enum AfterSelect: String {
    case copy, save, editor
}

/// Настройки скриншотов (UserDefaults).
enum ScreenshotSettings {
    private static var d: UserDefaults { .standard }
    static let modMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    static func registerDefaults() {
        d.register(defaults: [
            "shotEnabled": true,
            "shotKeyCode": 19, // «2»
            "shotMods": Int(NSEvent.ModifierFlags([.command, .shift]).rawValue),
            "shotKeyName": "2",
            "shotFullKeyCode": 18, // «1»
            "shotFullMods": Int(NSEvent.ModifierFlags([.command, .shift]).rawValue),
            "shotFullKeyName": "1",
            "shotAfter": AfterSelect.copy.rawValue,
        ])
    }

    static var enabled: Bool {
        get { d.bool(forKey: "shotEnabled") }
        set { d.set(newValue, forKey: "shotEnabled") }
    }

    static var keyCode: Int {
        get { d.integer(forKey: "shotKeyCode") }
        set { d.set(newValue, forKey: "shotKeyCode") }
    }

    static var mods: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: "shotMods"))).intersection(modMask) }
        set { d.set(Int(newValue.intersection(modMask).rawValue), forKey: "shotMods") }
    }

    static var keyName: String {
        get { d.string(forKey: "shotKeyName") ?? "?" }
        set { d.set(newValue, forKey: "shotKeyName") }
    }

    static var fullKeyCode: Int {
        get { d.integer(forKey: "shotFullKeyCode") }
        set { d.set(newValue, forKey: "shotFullKeyCode") }
    }

    static var fullMods: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: "shotFullMods"))).intersection(modMask) }
        set { d.set(Int(newValue.intersection(modMask).rawValue), forKey: "shotFullMods") }
    }

    static var fullKeyName: String {
        get { d.string(forKey: "shotFullKeyName") ?? "?" }
        set { d.set(newValue, forKey: "shotFullKeyName") }
    }

    static var after: AfterSelect {
        get { AfterSelect(rawValue: d.string(forKey: "shotAfter") ?? "") ?? .copy }
        set { d.set(newValue.rawValue, forKey: "shotAfter") }
    }

    static var saveDir: URL {
        get {
            if let p = d.string(forKey: "shotDir") { return URL(fileURLWithPath: p, isDirectory: true) }
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures/QuickTab Screenshots", isDirectory: true)
        }
        set { d.set(newValue.path, forKey: "shotDir") }
    }

    static var hotkeyDescription: String { symbols(mods) + keyName }
    static var fullHotkeyDescription: String { symbols(fullMods) + fullKeyName }

    static func symbols(_ m: NSEvent.ModifierFlags) -> String {
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        return s
    }

    // MARK: - Названия клавиш (по коду, чтобы не зависеть от раскладки)

    static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        49: "Space", 48: "⇥", 36: "↩", 51: "⌫", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func keyName(for code: UInt16) -> String {
        functionKeys[code] ?? names[code] ?? "#\(code)"
    }
}
