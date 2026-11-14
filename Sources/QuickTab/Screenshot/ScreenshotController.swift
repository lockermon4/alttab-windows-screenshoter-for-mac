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

    func capture() { start(full: false) }

    /// Весь монитор под курсором, без выделения; дальше — как в настройке «после выделения».
    func captureFullScreen() { start(full: true) }

    private func start(full: Bool) {
        guard ScreenshotSettings.enabled, isSupported, overlays.isEmpty, !capturing else { return }
        guard #available(macOS 14.0, *) else { return }
        // Не верим CGPreflightScreenCaptureAccess: он бывает «нет», когда снимать можно.
        // Просто пробуем снять, а помощь показываем, только если не вышло.
        capturing = true
        previousApp = NSWorkspace.shared.frontmostApplication
        let mouse = NSEvent.mouseLocation
        let screens = full ? [NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main].compactMap { $0 }
                           : NSScreen.screens
        var scales: [CGDirectDisplayID: CGFloat] = [:]
        for s in screens { scales[s.displayID] = s.backingScaleFactor }

        Task.detached(priority: .userInitiated) {
            let shots = await ScreenGrabber.shared.captureAll(scales: scales)
            await MainActor.run { self.present(shots, full: full) }
        }
    }

    private func present(_ shots: [CGDirectDisplayID: CGImage], full: Bool) {
        capturing = false
        guard !shots.isEmpty else {
            previousApp = nil
            showPermissionHelp()
            return
        }
        if full, ScreenshotSettings.after != .editor,
           let screen = NSScreen.screens.first(where: { shots[$0.displayID] != nil }), let img = shots[screen.displayID] {
            let save = ScreenshotSettings.after == .save
            finish(img, scale: CGFloat(img.width) / max(1, screen.frame.width), how: save ? .save : .copy, screenRect: screen.frame)
            if !save { Toast.show(NSLocalizedString("Screenshot copied", comment: "")) }
            return
        }
        for screen in NSScreen.screens {
            guard let img = shots[screen.displayID] else { continue }
            let w = ScreenshotOverlayWindow(screen: screen, image: img, controller: self)
            if full { w.overlayView.selectAll() }
            overlays.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        let main = overlays.first { NSMouseInRect(mouse, $0.frame, false) } ?? overlays.first
        for w in overlays { w.orderFrontRegardless() }
        main?.makeKeyAndOrderFront(nil)
        if let main { main.makeFirstResponder(main.overlayView) }
    }

    // MARK: - Разрешение «Запись экрана»

    private var permissionTimer: Timer?

    private func showPermissionHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("QuickTab can't capture the screen", comment: "")
        alert.informativeText = NSLocalizedString("Screen Recording permission is required.\n\nIf QuickTab is already enabled in the list but doesn't work, the entry is left over from an old build (it had a different signature). Click “Reset and allow again”, then enable QuickTab in the Settings that open. QuickTab will restart by itself.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Reset and allow again", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Open Settings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        switch alert.runModal() {
        case .alertFirstButtonReturn: resetPermission()
        case .alertSecondButtonReturn:
            Previews.shared.requestPermission()
            openScreenRecordingSettings()
            waitForPermissionAndRelaunch()
        default: break
        }
    }

    /// Удалить устаревшую запись в «Записи экрана», попросить заново и ждать, пока включат.
    func resetPermission() {
        let id = Bundle.main.bundleIdentifier ?? "io.github.lockermon4.quicktab"
        // tccutil ищет приложение по id через LaunchServices; без регистрации — ошибка -10814.
        let reg = Process()
        reg.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        reg.arguments = ["-f", Bundle.main.bundlePath]
        do { try reg.run(); reg.waitUntilExit() } catch { NSLog("QuickTab: lsregister: \(error)") }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "ScreenCapture", id]
        let err = Pipe()
        task.standardError = err
        var ok = false
        do { try task.run(); task.waitUntilExit(); ok = task.terminationStatus == 0 } catch { NSLog("QuickTab: tccutil: \(error)") }
        if !ok {
            // Раньше ошибка глоталась молча — и кнопка «не работала» без объяснений.
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            NSLog("QuickTab: tccutil reset failed: \(msg)")
            Toast.show(NSLocalizedString("Couldn't reset the permission — remove QuickTab in System Settings manually", comment: ""))
        }
        Previews.shared.requestPermission()
        if #available(macOS 14.0, *) {
            Task { await ScreenGrabber.shared.invalidate() }
        }
        openScreenRecordingSettings()
        waitForPermissionAndRelaunch()
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Как только разрешение появится — перезапуск (ScreenCaptureKit видит его только после перезапуска).
    private func waitForPermissionAndRelaunch() {
        permissionTimer?.invalidate()
        var ticks = 0
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            ticks += 1
            if CGPreflightScreenCaptureAccess() {
                t.invalidate()
                self?.permissionTimer = nil
                Toast.show(NSLocalizedString("Permission granted, restarting QuickTab…", comment: ""))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Self.relaunch() }
            } else if ticks > 300 {
                t.invalidate()
                self?.permissionTimer = nil
            }
        }
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
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
                Toast.show(String(format: NSLocalizedString("Saved: %@", comment: ""), url.lastPathComponent))
            } else {
                Toast.show(String(format: NSLocalizedString("Couldn't save to %@", comment: ""), ScreenshotSettings.saveDir.path))
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
        Toast.show(String(format: NSLocalizedString("Color %@ copied", comment: ""), hex))
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
            f.dateFormat = NSLocalizedString("yyyy-MM-dd 'at' HH.mm.ss", comment: "")
            let url = dir.appendingPathComponent(String(format: NSLocalizedString("Screenshot %@.png", comment: ""), f.string(from: Date())))
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
                    Toast.show(NSLocalizedString("No text found", comment: ""))
                } else {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    Toast.show(String(format: NSLocalizedString("Text copied (%ld lines)", comment: ""), lines.count))
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
                DispatchQueue.main.async { Toast.show(NSLocalizedString("Couldn't recognize text", comment: "")) }
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
