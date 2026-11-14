import AppKit

final class SwitcherPanel: NSPanel {
    private let effect = NSVisualEffectView()
    private var items: [ItemView] = []
    private var iconCache: [pid_t: NSImage] = [:]
    var onClick: ((Int) -> Void)?

    private enum Metrics {
        static let item = NSSize(width: 128, height: 124)
        static let icon: CGFloat = 72
        static let padding: CGFloat = 14
        static let spacing: CGFloat = 6
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.masksToBounds = true
        contentView = effect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present(_ windows: [WindowInfo], selected: Int) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        let m = Metrics.self
        let maxCols = max(1, Int((area.width * 0.9 - 2 * m.padding + m.spacing) / (m.item.width + m.spacing)))
        let maxRows = max(1, Int((area.height * 0.9 - 2 * m.padding + m.spacing) / (m.item.height + m.spacing)))
        let count = min(windows.count, maxCols * maxRows)
        let cols = min(count, maxCols)
        let rows = Int(ceil(Double(count) / Double(cols)))

        let size = NSSize(
            width: 2 * m.padding + CGFloat(cols) * m.item.width + CGFloat(cols - 1) * m.spacing,
            height: 2 * m.padding + CGFloat(rows) * m.item.height + CGFloat(rows - 1) * m.spacing)

        while items.count < count {
            let v = ItemView(iconSize: m.icon)
            v.onClick = { [weak self] i in self?.onClick?(i) }
            items.append(v)
            effect.addSubview(v)
        }
        for (i, v) in items.enumerated() {
            guard i < count else { v.isHidden = true; continue }
            let w = windows[i]
            let col = i % cols, row = i / cols
            v.frame = NSRect(
                x: m.padding + CGFloat(col) * (m.item.width + m.spacing),
                y: size.height - m.padding - CGFloat(row + 1) * m.item.height - CGFloat(row) * m.spacing,
                width: m.item.width, height: m.item.height)
            v.configure(index: i, icon: icon(for: w.pid), title: w.displayTitle,
                        dimmed: w.isMinimized || w.isAppHidden)
            v.isSelected = i == selected
            v.isHidden = false
        }

        setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                        width: size.width, height: size.height), display: true)
        orderFrontRegardless()
    }

    func select(_ index: Int) {
        for (i, v) in items.enumerated() where !v.isHidden { v.isSelected = i == index }
    }

    private func icon(for pid: pid_t) -> NSImage? {
        if let i = iconCache[pid] { return i }
        let i = NSRunningApplication(processIdentifier: pid)?.icon
        iconCache[pid] = i
        return i
    }
}

private final class ItemView: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var index = 0
    var onClick: ((Int) -> Void)?

    var isSelected = false {
        didSet {
            layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
                : NSColor.clear.cgColor
        }
    }

    init(iconSize: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame.size = NSSize(width: iconSize, height: iconSize)
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.alignment = .center
        label.textColor = .labelColor
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        label.cell?.wraps = true
        addSubview(iconView)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(index: Int, icon: NSImage?, title: String, dimmed: Bool) {
        self.index = index
        iconView.image = icon
        iconView.alphaValue = dimmed ? 0.45 : 1
        label.stringValue = title
        toolTip = title
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let s = iconView.frame.size
        iconView.frame.origin = NSPoint(x: (bounds.width - s.width) / 2, y: bounds.height - s.height - 8)
        label.frame = NSRect(x: 6, y: 4, width: bounds.width - 12, height: iconView.frame.minY - 6)
    }

    override func mouseDown(with event: NSEvent) { onClick?(index) }
}
