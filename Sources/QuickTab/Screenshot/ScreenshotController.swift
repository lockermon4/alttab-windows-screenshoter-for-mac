import AppKit
import Vision

/// Скриншоты со стоп-кадром: по горячей клавише снимаем все мониторы,
/// показываем снимок поверх всего и даём выделить область.
final class ScreenshotController {
    static let shared = ScreenshotController()

    enum Finish { case copy, save, pin, ocr }

    var isSupported: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    private var overlays: [ScreenshotOverlayWindow] = []
    private var pins: [PinWindow] = []
    private var capturing = false
    private var previousApp: NSRunningApplication?

    func screensChanged() {
        if #available(macOS 14.0, *) {
            Task { await ScreenGrabber.shared.invalidate() }
        }
    }

    // MARK: - Съёмка

    func capture() {
        guard ScreenshotSettings.enabled, overlays.isEmpty, !capturing else { return }
        guard #available(macOS 14.0, *) else { return }
        guard hasPermission else {
            Previews.shared.requestPermission()
            Toast.show("Разреши QuickTab «Запись экрана» и перезапусти его")
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        capturing = true
        previousApp = NSWorkspace.shared.frontmostApplication
        var scales: [CGDirectDisplayID: CGFloat] = [:]
        for s in NSScreen.screens { scales[s.displayID] = s.backingScaleFactor }

        Task.detached(priority: .userInitiated) {
            let shots = await ScreenGrabber.shared.captureAll(scales: scales)
            await MainActor.run { self.present(shots) }
        }
    }

    private func present(_ shots: [CGDirectDisplayID: CGImage]) {
        capturing = false
        guard !shots.isEmpty else {
            NSSound.beep()
            Toast.show("Не удалось снять экран. Проверь «Запись экрана» и перезапусти QuickTab")
            return
        }
        for screen in NSScreen.screens {
            guard let img = shots[screen.displayID] else { continue }
            overlays.append(ScreenshotOverlayWindow(screen: screen, image: img, controller: self))
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        let main = overlays.first { NSMouseInRect(mouse, $0.frame, false) } ?? overlays.first
        for w in overlays { w.orderFrontRegardless() }
        main?.makeKeyAndOrderFront(nil)
        if let main { main.makeFirstResponder(main.overlayView) }
    }

    /// Выделение может быть только на одном мониторе.
    func focus(_ view: ScreenshotOverlayView) {
        for w in overlays where w.overlayView !== view {
            w.overlayView.resetSelection()
        }
        if let w = view.window, !w.isKeyWindow {
            w.makeKeyAndOrderFront(nil)
        }
    }

    func closeAll(restoreFocus: Bool = true) {
        let list = overlays
        overlays = []
        for w in list {
            w.orderOut(nil)
            w.close()
        }
        if restoreFocus, let app = previousApp {
            if #available(macOS 14.0, *) { NSApp.yieldActivation(to: app) }
            app.activate(options: [])
        }
        previousApp = nil
    }

    // MARK: - Результат

    func finish(_ img: CGImage, scale: CGFloat, how: Finish, screenRect: CGRect) {
        closeAll(restoreFocus: how != .pin)
        switch how {
        case .copy:
            copyImage(img, scale: scale)
        case .save:
            copyImage(img, scale: scale)
            if let url = save(img, scale: scale) {
                Toast.show("Сохранено: \(url.lastPathComponent)")
            } else {
                Toast.show("Не удалось сохранить в \(ScreenshotSettings.saveDir.path)")
            }
        case .pin:
            showPin(img, scale: scale, frame: screenRect)
        case .ocr:
            recognizeText(img)
        }
    }

    func copyColor(_ hex: String) {
        closeAll()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(hex, forType: .string)
        Toast.show("Цвет \(hex) скопирован")
    }

    static func pngData(_ img: CGImage, scale: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: img)
        rep.size = NSSize(width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)
        return rep.representation(using: .png, properties: [:])
    }

    func copyImage(_ img: CGImage, scale: CGFloat) {
        let rep = NSBitmapImageRep(cgImage: img)
        rep.size = NSSize(width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)
        let item = NSPasteboardItem()
        if let png = rep.representation(using: .png, properties: [:]) { item.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item])
    }

    func save(_ img: CGImage, scale: CGFloat) -> URL? {
        let dir = ScreenshotSettings.saveDir
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd 'в' HH.mm.ss"
            let url = dir.appendingPathComponent("Скриншот \(f.string(from: Date())).png")
            guard let data = Self.pngData(img, scale: scale) else { return nil }
            try data.write(to: url)
            return url
        } catch {
            NSLog("QuickTab: save error: \(error)")
            return nil
        }
    }

    // MARK: - Распознавание текста

    func recognizeText(_ img: CGImage) {
        let request = VNRecognizeTextRequest { req, _ in
            let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async {
                let text = lines.joined(separator: "\n")
                if text.isEmpty {
                    Toast.show("Текст не найден")
                } else {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    Toast.show("Текст скопирован (\(lines.count) стр.)")
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ru-RU", "en-US"]
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try VNImageRequestHandler(cgImage: img).perform([request])
            } catch {
                DispatchQueue.main.async { Toast.show("Не удалось распознать текст") }
            }
        }
    }

    // MARK: - Закреп поверх окон

    private func showPin(_ img: CGImage, scale: CGFloat, frame: CGRect) {
        let w = PinWindow(image: img, scale: scale, frame: frame)
        pins.append(w)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] n in
            guard let closed = n.object as? PinWindow else { return }
            self?.pins.removeAll { $0 === closed }
        }
        w.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Всплывающая подсказка

enum Toast {
    private static var panel: NSPanel?

    static func show(_ text: String) {
        panel?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 28, height: label.frame.height + 16)
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 80)
        let p = NSPanel(contentRect: CGRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let bg = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.appearance = NSAppearance(named: .darkAqua)
        bg.wantsLayer = true
        bg.layer?.cornerRadius = size.height / 2
        bg.layer?.masksToBounds = true
        label.frame.origin = CGPoint(x: 14, y: 8)
        bg.addSubview(label)
        p.contentView = bg
        p.orderFrontRegardless()
        panel = p

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard panel === p else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                p.animator().alphaValue = 0
            }, completionHandler: {
                p.orderOut(nil)
                if panel === p { panel = nil }
            })
        }
    }
}
