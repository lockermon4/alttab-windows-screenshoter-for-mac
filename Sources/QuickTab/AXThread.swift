import Foundation

/// Отдельный поток со своим run loop. На нём живут все AXObserver'ы и все
/// AX-запросы трекера, поэтому главный поток (UI) никогда не ждёт приложения.
final class AXThread {
    private(set) var runLoop: CFRunLoop!
    private let ready = DispatchSemaphore(value: 0)

    init(name: String) {
        let thread = Thread { [unowned self] in
            self.runLoop = CFRunLoopGetCurrent()
            // Пустой источник, чтобы run loop не завершался.
            var ctx = CFRunLoopSourceContext()
            let keepAlive = CFRunLoopSourceCreate(nil, 0, &ctx)
            CFRunLoopAddSource(self.runLoop, keepAlive, .defaultMode)
            self.ready.signal()
            CFRunLoopRun()
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    func async(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    func after(_ seconds: Double, _ block: @escaping () -> Void) {
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + seconds, 0, 0, 0) { _ in block() }
        CFRunLoopAddTimer(runLoop, timer, .defaultMode)
    }
}
