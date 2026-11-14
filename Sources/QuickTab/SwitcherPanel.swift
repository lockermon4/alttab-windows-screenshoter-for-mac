import AppKit

final class SwitcherPanel: NSPanel {
    private let effect = NSVisualEffectView()
    private var items: [ItemView] = []
    private var iconCache: [pid_t: NSImage] = [:]
    var onClick: ((Int) -> Void)?

    struct Metrics {
        let item: NSSize
        let padding: CGFloat = 14
        let spacing: CGFloat = 8

        static let icons = Metrics(item: NSSize(width: 128, height: 124))
        static let previews = Metrics(item: NSSize(width: Previews.maxSide + 20, height: 180))
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

    func present(_ windows: [WindowInfo], selected: Int, previews: Bool) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        let m = previews ? Metrics.previews : Metrics.icons
        let maxCols = max(1, Int((area.width * 0.92 - 2 * m.padding + m.spacing) / (m.item.width + m.spacing)))
        let maxRows = max(1, Int((area.height * 0.9 - 2 * m.padding + m.spacing) / (m.item.height + m.spacing)))
        let count = min(windows.count, maxCols * maxRows)
        let cols = min(count, maxCols)
        let rows = Int(ceil(Double(count) / Double(cols)))

        let size = NSSize(
            width: 2 * m.padding + CGFloat(cols) * m.item.width + CGFloat(cols - 1) * m.spacing,
            height: 2 * m.padding + CGFloat(rows) * m.item.height + CGFloat(rows - 1) * m.spacing)

        while items.count < count {
            let v = ItemView()
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
            v.configure(index: i, windowID: w.id, icon: icon(for: w.pid), title: w.displayTitle,
                        dimmed: w.isMinimized || w.isAppHidden,
                        previewMode: previews,
                        preview: previews ? Previews.shared.image(for: w.id) : nil)
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

    func setPreview(_ id: CGWindowID, _ image: NSImage) {
        guard isVisible else { return }
        for v in items where !v.isHidden && v.windowID == id { v.setPreview(image) }
    }

    private func icon(for pid: pid_t) -> NSImage? {
        if let i = iconCache[pid] { return i }
        let i = NSRunningApplication(processIdentifier: pid)?.icon
        iconCache[pid] = i
        return i
    }
}

private final class ItemView: NSView {
    private let previewView = NSImageView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var index = 0
    private var previewMode = false
    private(set) var windowID: CGWindowID = 0
    var onClick: ((Int) -> Void)?

    var isSelected = false {
        didSet {
            layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
                : NSColor.clear.cgColor
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        previewView.imageScaling = .scaleProportionallyDown
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = 6
        previewView.layer?.masksToBounds = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        addSubview(previewView)
        addSubview(iconView)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(index: Int, windowID: CGWindowID, icon: NSImage?, title: String,
                   dimmed: Bool, previewMode: Bool, preview: NSImage?) {
        self.index = index
        self.windowID = windowID
        self.previewMode = previewMode
        iconView.image = icon
        previewView.image = preview
        previewView.isHidden = !previewMode
        let alpha: CGFloat = dimmed ? 0.45 : 1
        iconView.alphaValue = alpha
        previewView.alphaValue = alpha
        label.stringValue = title
        label.alignment = previewMode ? .left : .center
        label.maximumNumberOfLines = previewMode ? 1 : 2
        label.cell?.wraps = !previewMode
        toolTip = title
        needsLayout = true
    }

    func setPreview(_ image: NSImage) {
        previewView.image = image
        needsLayout = true
    }

    override func layout() {
        super.layout()
        if previewMode {
            let pad: CGFloat = 10
            let footer: CGFloat = 30
            previewView.frame = NSRect(x: pad, y: footer, width: bounds.width - 2 * pad,
                                       height: bounds.height - footer - pad)
            if previewView.image != nil {
                // Иконка-значок внизу слева, рядом заголовок.
                iconView.frame = NSRect(x: pad, y: 5, width: 22, height: 22)
                label.frame = NSRect(x: pad + 28, y: 7, width: bounds.width - 2 * pad - 28, height: 16)
            } else {
                // Снимка ещё нет — крупная иконка по центру области превью.
                let s: CGFloat = 64
                iconView.frame = NSRect(x: (bounds.width - s) / 2, y: previewView.frame.midY - s / 2, width: s, height: s)
                label.frame = NSRect(x: pad, y: 7, width: bounds.width - 2 * pad, height: 16)
            }
        } else {
            let s: CGFloat = 72
            iconView.frame = NSRect(x: (bounds.width - s) / 2, y: bounds.height - s - 8, width: s, height: s)
            label.frame = NSRect(x: 6, y: 4, width: bounds.width - 12, height: iconView.frame.minY - 6)
        }
    }

    override func mouseDown(with event: NSEvent) { onClick?(index) }
}
