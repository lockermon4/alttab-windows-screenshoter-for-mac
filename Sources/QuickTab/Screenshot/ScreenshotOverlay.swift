import AppKit

/// Окно со стоп-кадром одного монитора.
final class ScreenshotOverlayWindow: NSWindow {
    let overlayView: ScreenshotOverlayView

    init(screen: NSScreen, image: CGImage, controller: ScreenshotController) {
        let size = screen.frame.size
        overlayView = ScreenshotOverlayView(frame: CGRect(origin: .zero, size: size), image: image, controller: controller)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // Картинка — фоном через слой (рисует GPU), поверх прозрачный слой с выделением и рисунками.
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        container.wantsLayer = true
        let bg = NSView(frame: container.bounds)
        bg.wantsLayer = true
        bg.layer?.contents = image
        bg.layer?.contentsGravity = .resize
        bg.autoresizingMask = [.width, .height]
        container.addSubview(bg)
        overlayView.autoresizingMask = [.width, .height]
        container.addSubview(overlayView)
        contentView = container
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Выделение, рисование, лупа. Координаты — точки, начало в левом верхнем углу (isFlipped).
final class ScreenshotOverlayView: NSView, NSTextFieldDelegate {
    enum Tool { case pen, line, arrow, rect, ellipse, marker, text, pixelate }
    enum Handle: CaseIterable { case tl, t, tr, r, br, b, bl, l }
    private enum Mode { case none, selecting, moving, resizing, drawing }

    struct Shape {
        var tool: Tool
        var color: NSColor
        var width: CGFloat
        var points: [CGPoint]
        var text = ""

        var rect: CGRect {
            guard let a = points.first, let b = points.last else { return .zero }
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        }
    }

    static let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .white, .black]
    static let widths: [CGFloat] = [2, 4, 8]

    let image: CGImage
    let scale: CGFloat
    private unowned let controller: ScreenshotController

    private(set) var sel: CGRect = .zero
    private var mode: Mode = .none
    private var handle: Handle = .br
    private var dragStart: CGPoint = .zero
    private var dragOrig: CGRect = .zero
    private(set) var tool: Tool?
    private(set) var colorIndex = 0
    private(set) var widthIndex = 1
    private var shapes: [Shape] = []
    private var current: Shape?
    private var mouse: CGPoint = CGPoint(x: -1000, y: -1000)
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private let toolbar = ScreenshotToolbar()

    var color: NSColor { Self.colors[colorIndex] }
    var lineWidth: CGFloat { Self.widths[widthIndex] }

    init(frame: CGRect, image: CGImage, controller: ScreenshotController) {
        self.image = image
        self.controller = controller
        scale = CGFloat(image.width) / max(1, frame.width)
        super.init(frame: frame)
        wantsLayer = true
        toolbar.overlay = self
        toolbar.isHidden = true
        addSubview(toolbar)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let w = window else { return }
        mouse = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        w.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Рисование

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        if sel.isEmpty {
            ctx.fill(bounds)
        } else {
            ctx.addRect(bounds)
            ctx.addRect(sel)
            ctx.fillPath(using: .evenOdd)

            ctx.saveGState()
            ctx.clip(to: sel)
            drawShapes(shapes + (current.map { [$0] } ?? []), ctx: ctx)
            ctx.restoreGState()

            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(sel.insetBy(dx: 0.5, dy: 0.5))
            for h in Handle.allCases {
                let p = point(h)
                let r = CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(r)
                ctx.stroke(r)
            }
            drawSizeLabel()
        }
        if sel.isEmpty || mode == .selecting {
            drawLoupe(ctx)
        }
    }

    private func drawSizeLabel() {
        let text = "\(Int((sel.width * scale).rounded())) × \(Int((sel.height * scale).rounded()))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let sz = str.size()
        let y = sel.minY > 26 ? sel.minY - 24 : sel.minY + 4
        let box = CGRect(x: sel.minX, y: y, width: sz.width + 12, height: 20)
        NSColor(white: 0.12, alpha: 0.88).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        str.draw(at: CGPoint(x: box.minX + 6, y: box.minY + (20 - sz.height) / 2))
    }

    func drawShapes(_ list: [Shape], ctx: CGContext) {
        for s in list {
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setFillColor(s.color.cgColor)
            ctx.setLineWidth(s.width)
            let a = s.points.first ?? .zero
            let b = s.points.last ?? .zero
            switch s.tool {
            case .pen:
                strokePath(s.points, ctx: ctx)
            case .marker:
                ctx.setBlendMode(.multiply)
                ctx.setStrokeColor(s.color.withAlphaComponent(0.45).cgColor)
                ctx.setLineWidth(s.width * 5)
                ctx.setLineCap(.butt)
                strokePath(s.points, ctx: ctx)
            case .line:
                ctx.move(to: a)
                ctx.addLine(to: b)
                ctx.strokePath()
            case .arrow:
                drawArrow(from: a, to: b, width: s.width, ctx: ctx)
            case .rect:
                ctx.stroke(s.rect)
            case .ellipse:
                ctx.strokeEllipse(in: s.rect)
            case .text:
                let font = NSFont.boldSystemFont(ofSize: 14 + s.width * 3)
                NSAttributedString(string: s.text, attributes: [.font: font, .foregroundColor: s.color])
                    .draw(at: CGPoint(x: a.x + 2, y: a.y + 1))
            case .pixelate:
                if let px = pixelated(s.rect) {
                    ctx.interpolationQuality = .none
                    drawUpright(px, in: s.rect, ctx: ctx)
                }
            }
            ctx.restoreGState()
        }
    }

    private func strokePath(_ pts: [CGPoint], ctx: CGContext) {
        guard let first = pts.first else { return }
        ctx.move(to: first)
        for p in pts.dropFirst() { ctx.addLine(to: p) }
        if pts.count == 1 { ctx.addLine(to: first) }
        ctx.strokePath()
    }

    private func drawArrow(from a: CGPoint, to b: CGPoint, width w: CGFloat, ctx: CGContext) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 1 else { return }
        let ux = dx / len, uy = dy / len
        let size = 10 + w * 3
        let left = CGPoint(x: b.x - ux * size - uy * size * 0.5, y: b.y - uy * size + ux * size * 0.5)
        let right = CGPoint(x: b.x - ux * size + uy * size * 0.5, y: b.y - uy * size - ux * size * 0.5)
        let base = CGPoint(x: b.x - ux * size * 0.8, y: b.y - uy * size * 0.8)
        ctx.move(to: a)
        ctx.addLine(to: base)
        ctx.strokePath()
        ctx.move(to: b)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
    }

    /// Нарисовать CGImage «правильной стороной вверх» в контексте с осью Y вниз.
    private func drawUpright(_ img: CGImage, in r: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
        ctx.restoreGState()
    }

    private func pixelRect(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    private func pixelated(_ r: CGRect) -> CGImage? {
        let pr = pixelRect(r)
        guard pr.width >= 2, pr.height >= 2, let crop = image.cropping(to: pr) else { return nil }
        let block = max(4, 10 * scale)
        let w = max(1, Int(pr.width / block)), h = max(1, Int(pr.height / block))
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.interpolationQuality = .medium
        c.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        return c.makeImage()
    }

    // MARK: - Лупа и цвет под курсором

    private func pixelUnderMouse() -> (x: Int, y: Int) {
        (min(max(0, Int(mouse.x * scale)), image.width - 1), min(max(0, Int(mouse.y * scale)), image.height - 1))
    }

    private func hexColor(x: Int, y: Int) -> String {
        guard let one = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return "#000000" }
        var buf = [UInt8](repeating: 0, count: 4)
        buf.withUnsafeMutableBytes { raw in
            guard let c = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            c.draw(one, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return String(format: "#%02X%02X%02X", buf[0], buf[1], buf[2])
    }

    private let loupeSize: CGFloat = 120
    private let loupeCells = 15

    private func loupeFrame(at m: CGPoint) -> CGRect {
        var lx = m.x + 20, ly = m.y + 20
        if lx + loupeSize > bounds.maxX { lx = m.x - 20 - loupeSize }
        if ly + loupeSize + 40 > bounds.maxY { ly = m.y - 20 - loupeSize - 40 }
        return CGRect(x: lx, y: ly, width: loupeSize, height: loupeSize + 38)
    }

    private func drawLoupe(_ ctx: CGContext) {
        guard bounds.contains(mouse) else { return }
        let frame = loupeFrame(at: mouse)
        let target = CGRect(x: frame.minX, y: frame.minY, width: loupeSize, height: loupeSize)
        let (px, py) = pixelUnderMouse()
        let half = loupeCells / 2
        let cell = loupeSize / CGFloat(loupeCells)

        ctx.saveGState()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(target)
        let src = CGRect(x: px - half, y: py - half, width: loupeCells, height: loupeCells)
        let clipped = src.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        if !clipped.isNull, let crop = image.cropping(to: clipped) {
            let t = CGRect(x: target.minX + (clipped.minX - src.minX) * cell,
                           y: target.minY + (clipped.minY - src.minY) * cell,
                           width: clipped.width * cell, height: clipped.height * cell)
            ctx.interpolationQuality = .none
            drawUpright(crop, in: t, ctx: ctx)
        }
        let c = CGRect(x: target.minX + cell * CGFloat(half), y: target.minY + cell * CGFloat(half), width: cell, height: cell)
        ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(cell)
        ctx.strokeLineSegments(between: [
            CGPoint(x: target.minX, y: c.midY), CGPoint(x: c.minX, y: c.midY),
            CGPoint(x: c.maxX, y: c.midY), CGPoint(x: target.maxX, y: c.midY),
            CGPoint(x: c.midX, y: target.minY), CGPoint(x: c.midX, y: c.minY),
            CGPoint(x: c.midX, y: c.maxY), CGPoint(x: c.midX, y: target.maxY),
        ])
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(c)
        ctx.stroke(target)

        let info = CGRect(x: target.minX, y: target.maxY, width: loupeSize, height: 38)
        ctx.setFillColor(NSColor(white: 0.12, alpha: 0.92).cgColor)
        ctx.fill(info)
        ctx.restoreGState()

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let str = NSAttributedString(string: "\(px), \(py)\n\(hexColor(x: px, y: py))   C — копировать",
                                     attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
                                                  .foregroundColor: NSColor.white, .paragraphStyle: para])
        str.draw(in: info.insetBy(dx: 2, dy: 4))
    }

    // MARK: - Геометрия выделения

    private func point(_ h: Handle) -> CGPoint {
        switch h {
        case .tl: return CGPoint(x: sel.minX, y: sel.minY)
        case .t: return CGPoint(x: sel.midX, y: sel.minY)
        case .tr: return CGPoint(x: sel.maxX, y: sel.minY)
        case .r: return CGPoint(x: sel.maxX, y: sel.midY)
        case .br: return CGPoint(x: sel.maxX, y: sel.maxY)
        case .b: return CGPoint(x: sel.midX, y: sel.maxY)
        case .bl: return CGPoint(x: sel.minX, y: sel.maxY)
        case .l: return CGPoint(x: sel.minX, y: sel.midY)
        }
    }

    private func hitHandle(_ p: CGPoint) -> Handle? {
        guard !sel.isEmpty else { return nil }
        return Handle.allCases.first { h in
            let q = point(h)
            return abs(q.x - p.x) <= 7 && abs(q.y - p.y) <= 7
        }
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(0, p.x), bounds.width), y: min(max(0, p.y), bounds.height))
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - Мышь

    override func mouseDown(with e: NSEvent) {
        let p = clamp(convert(e.locationInWindow, from: nil))
        mouse = p
        if e.clickCount == 2 && tool == nil && sel.contains(p) {
            finish(.copy)
            return
        }
        commitText()
        controller.focus(self)

        if !sel.isEmpty, let t = tool {
            if t == .text {
                startText(at: p)
            } else {
                current = Shape(tool: t, color: color, width: lineWidth, points: [p])
                mode = .drawing
            }
            return
        }

        if let h = hitHandle(p) {
            mode = .resizing
            handle = h
        } else if !sel.isEmpty && sel.contains(p) {
            mode = .moving
            NSCursor.closedHand.set()
        } else {
            shapes.removeAll()
            mode = .selecting
            sel = CGRect(origin: p, size: .zero)
        }
        dragStart = p
        dragOrig = sel
        layoutToolbar()
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        let p = clamp(convert(e.locationInWindow, from: nil))
        mouse = p
        switch mode {
        case .selecting:
            sel = rect(dragStart, p)
        case .moving:
            var r = dragOrig.offsetBy(dx: p.x - dragStart.x, dy: p.y - dragStart.y)
            r.origin.x = min(max(0, r.minX), bounds.width - r.width)
            r.origin.y = min(max(0, r.minY), bounds.height - r.height)
            sel = r
        case .resizing:
            var minX = dragOrig.minX, maxX = dragOrig.maxX, minY = dragOrig.minY, maxY = dragOrig.maxY
            if [.tl, .l, .bl].contains(handle) { minX = p.x }
            if [.tr, .r, .br].contains(handle) { maxX = p.x }
            if [.tl, .t, .tr].contains(handle) { minY = p.y }
            if [.bl, .b, .br].contains(handle) { maxY = p.y }
            sel = rect(CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY))
        case .drawing:
            guard var c = current else { break }
            if c.tool == .pen || c.tool == .marker {
                c.points.append(p)
            } else {
                var q = p
                if e.modifierFlags.contains(.shift), let a = c.points.first {
                    let dx = p.x - a.x, dy = p.y - a.y
                    if c.tool == .rect || c.tool == .ellipse || c.tool == .pixelate {
                        let d = max(abs(dx), abs(dy))
                        q = CGPoint(x: a.x + (dx >= 0 ? d : -d), y: a.y + (dy >= 0 ? d : -d))
                    } else {
                        // линии и стрелки — шаг 45°
                        let ang = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
                        let len = hypot(dx, dy)
                        q = CGPoint(x: a.x + cos(ang) * len, y: a.y + sin(ang) * len)
                    }
                }
                if c.points.count == 1 { c.points.append(q) } else { c.points[c.points.count - 1] = q }
            }
            current = c
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        if mode == .drawing, let c = current {
            if c.points.count > 1 { shapes.append(c) }
            current = nil
        }
        let wasSelecting = mode == .selecting
        if (mode == .selecting || mode == .resizing) && (sel.width < 3 || sel.height < 3) {
            sel = .zero
        }
        mode = .none
        if wasSelecting && !sel.isEmpty && ScreenshotSettings.after != .editor && !e.modifierFlags.contains(.option) {
            finish(ScreenshotSettings.after == .save ? .save : .copy)
            return
        }
        layoutToolbar()
        updateCursor()
        needsDisplay = true
    }

    override func mouseMoved(with e: NSEvent) {
        let old = mouse
        mouse = convert(e.locationInWindow, from: nil)
        updateCursor()
        if sel.isEmpty {
            setNeedsDisplay(loupeFrame(at: old).insetBy(dx: -4, dy: -4))
            setNeedsDisplay(loupeFrame(at: mouse).insetBy(dx: -4, dy: -4))
        }
    }

    override func mouseExited(with event: NSEvent) {
        if sel.isEmpty {
            setNeedsDisplay(loupeFrame(at: mouse).insetBy(dx: -4, dy: -4))
            mouse = CGPoint(x: -1000, y: -1000)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if sel.isEmpty { controller.closeAll() } else { resetSelection() }
    }

    private func updateCursor() {
        if !toolbar.isHidden && toolbar.frame.contains(mouse) {
            NSCursor.arrow.set()
        } else if let t = tool, !sel.isEmpty {
            (t == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
        } else if let h = hitHandle(mouse) {
            if h == .l || h == .r { NSCursor.resizeLeftRight.set() }
            else if h == .t || h == .b { NSCursor.resizeUpDown.set() }
            else { NSCursor.crosshair.set() }
        } else if !sel.isEmpty && sel.contains(mouse) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    func resetSelection() {
        commitText()
        sel = .zero
        shapes.removeAll()
        current = nil
        mode = .none
        tool = nil
        toolbar.isHidden = true
        needsDisplay = true
    }

    // MARK: - Панель инструментов

    private func layoutToolbar() {
        guard !sel.isEmpty, mode == .none else {
            toolbar.isHidden = true
            return
        }
        toolbar.refresh()
        let s = toolbar.frame.size
        let x = min(max(0, sel.maxX - s.width), bounds.width - s.width)
        var y = sel.maxY + 8
        if y + s.height > bounds.height {
            y = sel.minY - s.height - 8
            if y < 0 { y = sel.maxY - s.height - 8 }
        }
        toolbar.setFrameOrigin(CGPoint(x: x, y: y))
        toolbar.isHidden = false
    }

    func setTool(_ t: Tool?) {
        commitText()
        tool = t
        toolbar.refresh()
        updateCursor()
    }

    func nextColor() {
        colorIndex = (colorIndex + 1) % Self.colors.count
        toolbar.refresh()
    }

    func nextWidth() {
        widthIndex = (widthIndex + 1) % Self.widths.count
        toolbar.refresh()
    }

    func undo() {
        guard !shapes.isEmpty else { return }
        shapes.removeLast()
        needsDisplay = true
    }

    // MARK: - Текст

    private func startText(at p: CGPoint) {
        let size = 14 + lineWidth * 3
        let f = NSTextField(frame: CGRect(x: p.x, y: p.y, width: 320, height: size + 8))
        f.font = .boldSystemFont(ofSize: size)
        f.textColor = color
        f.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        f.drawsBackground = true
        f.isBordered = false
        f.focusRingType = .none
        f.placeholderString = "Текст…"
        f.target = self
        f.action = #selector(textEntered)
        f.delegate = self
        addSubview(f)
        window?.makeFirstResponder(f)
        textField = f
        textOrigin = p
    }

    @objc private func textEntered() { commitText() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelText()
            return true
        }
        return false
    }

    private func commitText() {
        guard let f = textField else { return }
        textField = nil
        let s = f.stringValue
        f.removeFromSuperview()
        if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shapes.append(Shape(tool: .text, color: color, width: lineWidth, points: [textOrigin], text: s))
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func cancelText() {
        guard let f = textField else { return }
        textField = nil
        f.removeFromSuperview()
        window?.makeFirstResponder(self)
    }

    // MARK: - Клавиатура

    private static let toolKeys: [UInt16: Tool] = [
        11: .pen, 37: .line, 0: .arrow, 15: .rect, 14: .ellipse, 46: .marker, 17: .text, 7: .pixelate,
    ]

    override func keyDown(with e: NSEvent) {
        let cmd = e.modifierFlags.contains(.command)
        switch e.keyCode {
        case 53: controller.closeAll(); return               // Esc
        case 36, 76: finish(.copy); return                    // Return / Enter
        case 123, 124, 125, 126: nudgeCursor(e); return      // стрелки
        default: break
        }
        if cmd {
            switch e.keyCode {
            case 8: finish(.copy)                             // ⌘C
            case 1: finish(.save)                             // ⌘S
            case 6: undo()                                    // ⌘Z
            case 0:                                           // ⌘A
                sel = bounds
                layoutToolbar()
                needsDisplay = true
            default: super.keyDown(with: e)
            }
            return
        }
        switch e.keyCode {
        case 8: // C — цвет под курсором
            let (x, y) = pixelUnderMouse()
            controller.copyColor(hexColor(x: x, y: y))
        case 35: finish(.pin)  // P
        case 31: finish(.ocr)  // O
        case 9: setTool(nil)   // V
        default:
            if !sel.isEmpty, let t = Self.toolKeys[e.keyCode] { setTool(t) }
        }
    }

    private func nudgeCursor(_ e: NSEvent) {
        let step: CGFloat = e.modifierFlags.contains(.shift) ? 10 : 1
        var d = CGPoint.zero
        switch e.keyCode {
        case 123: d.x = -step
        case 124: d.x = step
        case 125: d.y = step
        default: d.y = -step
        }
        guard let primary = NSScreen.screens.first else { return }
        let loc = NSEvent.mouseLocation
        let old = mouse
        CGWarpMouseCursorPosition(CGPoint(x: loc.x + d.x, y: primary.frame.maxY - loc.y + d.y))
        CGAssociateMouseAndMouseCursorPosition(1)
        mouse = clamp(CGPoint(x: mouse.x + d.x, y: mouse.y + d.y))
        if sel.isEmpty {
            setNeedsDisplay(loupeFrame(at: old).insetBy(dx: -4, dy: -4))
            setNeedsDisplay(loupeFrame(at: mouse).insetBy(dx: -4, dy: -4))
        }
    }

    // MARK: - Готово

    func finish(_ how: ScreenshotController.Finish) {
        guard !sel.isEmpty else { return }
        commitText()
        guard let img = render(withShapes: how != .ocr) else { return }
        var screenRect = convert(sel, to: nil)
        if let w = window { screenRect = w.convertToScreen(screenRect) }
        controller.finish(img, scale: scale, how: how, screenRect: screenRect)
    }

    private func render(withShapes: Bool) -> CGImage? {
        let pr = pixelRect(sel)
        guard !pr.isEmpty, let crop = image.cropping(to: pr) else { return nil }
        guard withShapes, !shapes.isEmpty else { return crop }

        let space: CGColorSpace
        if let cs = crop.colorSpace, cs.model == .rgb { space = cs }
        else { space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB() }
        guard let ctx = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return crop }
        // Ось Y вниз — как в окне.
        ctx.translateBy(x: 0, y: CGFloat(crop.height))
        ctx.scaleBy(x: 1, y: -1)
        drawUpright(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height), ctx: ctx)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -pr.minX / scale, y: -pr.minY / scale)
        ctx.clip(to: sel)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        drawShapes(shapes, ctx: ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}

// MARK: - Панель инструментов

final class ScreenshotToolbar: NSView {
    weak var overlay: ScreenshotOverlayView?
    private var toolButtons: [(ScreenshotOverlayView.Tool?, NSButton)] = []
    private var colorButton: NSButton!
    private var widthButton: NSButton!

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.95).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        let tools: [(ScreenshotOverlayView.Tool?, String, String)] = [
            (nil, "cursorarrow", "Выделение (V)"),
            (.pen, "pencil", "Карандаш (B)"),
            (.line, "line.diagonal", "Линия (L)"),
            (.arrow, "arrow.up.right", "Стрелка (A)"),
            (.rect, "rectangle", "Прямоугольник (R)"),
            (.ellipse, "circle", "Эллипс (E)"),
            (.marker, "highlighter", "Маркер (M)"),
            (.text, "textformat", "Текст (T)"),
            (.pixelate, "checkerboard.rectangle", "Скрыть пикселями (X)"),
        ]
        for (i, (t, sym, tip)) in tools.enumerated() {
            let b = makeButton(sym, tip, #selector(toolClicked(_:)))
            b.tag = i
            toolButtons.append((t, b))
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(separator())
        colorButton = makeButton("circle.fill", "Цвет (клик — следующий)", #selector(colorClicked))
        stack.addArrangedSubview(colorButton)
        widthButton = makeButton("lineweight", "Толщина (клик — следующая)", #selector(widthClicked))
        stack.addArrangedSubview(widthButton)
        stack.addArrangedSubview(separator())
        let actions: [(String, String, Selector)] = [
            ("arrow.uturn.backward", "Отменить (⌘Z)", #selector(undoClicked)),
            ("text.viewfinder", "Распознать текст и скопировать (O)", #selector(ocrClicked)),
            ("pin", "Закрепить поверх окон (P)", #selector(pinClicked)),
            ("square.and.arrow.down", "Сохранить в папку (⌘S)", #selector(saveClicked)),
            ("doc.on.doc", "Копировать (↩ / ⌘C)", #selector(copyClicked)),
            ("xmark", "Закрыть (Esc)", #selector(closeClicked)),
        ]
        for (sym, tip, sel) in actions {
            stack.addArrangedSubview(makeButton(sym, tip, sel))
        }

        let size = stack.fittingSize
        stack.frame = CGRect(origin: .zero, size: size)
        addSubview(stack)
        setFrameSize(size)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Клики мимо кнопок не должны уходить в окно выделения.
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}

    private func makeButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage()
        let b = NSButton(image: img, target: self, action: action)
        b.isBordered = false
        b.toolTip = tip
        b.contentTintColor = NSColor(white: 0.92, alpha: 1)
        b.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        b.wantsLayer = true
        b.layer?.cornerRadius = 6
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return b
    }

    private func separator() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.18).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return v
    }

    func refresh() {
        guard let o = overlay else { return }
        for (t, b) in toolButtons {
            let on = t == o.tool
            b.layer?.backgroundColor = on ? NSColor.systemBlue.cgColor : NSColor.clear.cgColor
            b.contentTintColor = on ? .white : NSColor(white: 0.92, alpha: 1)
        }
        colorButton.contentTintColor = o.color
        let weights: [NSFont.Weight] = [.ultraLight, .regular, .heavy]
        widthButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: weights[o.widthIndex])
    }

    @objc private func toolClicked(_ sender: NSButton) { overlay?.setTool(toolButtons[sender.tag].0) }
    @objc private func colorClicked() { overlay?.nextColor() }
    @objc private func widthClicked() { overlay?.nextWidth() }
    @objc private func undoClicked() { overlay?.undo() }
    @objc private func ocrClicked() { overlay?.finish(.ocr) }
    @objc private func pinClicked() { overlay?.finish(.pin) }
    @objc private func saveClicked() { overlay?.finish(.save) }
    @objc private func copyClicked() { overlay?.finish(.copy) }
    @objc private func closeClicked() { ScreenshotController.shared.closeAll() }
}
