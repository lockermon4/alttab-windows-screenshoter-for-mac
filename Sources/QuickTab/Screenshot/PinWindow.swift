import AppKit

/// Кусок скриншота, закреплённый поверх всех окон.
/// Тащи мышью, колесо — масштаб, двойной клик или Esc — закрыть, правый клик — меню.
final class PinWindow: NSPanel {
    let cgImage: CGImage
    let scale: CGFloat
    private let baseSize: NSSize
    private var zoom: CGFloat = 1

    init(image: CGImage, scale: CGFloat, frame: CGRect) {
        cgImage = image
        self.scale = scale
        baseSize = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        super.init(contentRect: CGRect(origin: frame.origin, size: baseSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = PinView(frame: CGRect(origin: .zero, size: baseSize))
        v.image = NSImage(cgImage: image, size: baseSize)
        v.autoresizingMask = [.width, .height]
        contentView = v
    }

    override var canBecomeKey: Bool { true }

    func zoom(by factor: CGFloat) {
        zoom = min(5, max(0.2, zoom * factor))
        let f = frame
        let size = NSSize(width: baseSize.width * zoom, height: baseSize.height * zoom)
        setFrame(CGRect(x: f.minX, y: f.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    @objc func copyImage() {
        ScreenshotController.shared.copyImage(cgImage, scale: scale)
        Toast.show("Скопировано")
    }

    @objc func closePin() { close() }
}

private final class PinView: NSView {
    var image: NSImage?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds)
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.close()
        } else {
            window?.performDrag(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let w = window as? PinWindow, event.scrollingDeltaY != 0 else { return }
        w.zoom(by: event.scrollingDeltaY > 0 ? 1.08 : 1 / 1.08)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let w = window as? PinWindow else { return }
        let menu = NSMenu()
        let copy = NSMenuItem(title: "Копировать", action: #selector(PinWindow.copyImage), keyEquivalent: "")
        copy.target = w
        menu.addItem(copy)
        let close = NSMenuItem(title: "Закрыть", action: #selector(PinWindow.closePin), keyEquivalent: "")
        close.target = w
        menu.addItem(close)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.close()
        } else if event.modifierFlags.contains(.command) && event.keyCode == 8 {
            (window as? PinWindow)?.copyImage()
        } else {
            super.keyDown(with: event)
        }
    }
}
