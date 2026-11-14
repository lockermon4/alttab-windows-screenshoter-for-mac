import AppKit

final class SwitcherController {
    private let panel = SwitcherPanel()
    private var windows: [WindowInfo] = []
    private var session: [WindowInfo]?
    private var index = 0
    private var showWork: DispatchWorkItem?

    /// Задержка перед показом панели: быстрое ⌥Tab просто переключает
    /// на предыдущее окно, не рисуя ничего.
    var showDelay: TimeInterval = 0.12
    var modifier: CGEventFlags = .maskAlternate

    init() {
        panel.onClick = { [weak self] i in
            self?.index = i
            self?.commit()
        }
        Previews.shared.onUpdate = { [weak self] id, img in self?.panel.setPreview(id, img) }
    }

    private var warmedUp = false

    func update(_ list: [WindowInfo]) {
        windows = list
        Previews.shared.prune(keeping: Set(list.map(\.id)))
        if !warmedUp && !list.isEmpty {
            warmedUp = true
            warmUpPreviews()
        }
    }

    /// Сделать снимки заранее, чтобы при первом ⌥Tab превью уже были.
    func warmUpPreviews() {
        Previews.shared.refresh(Array(windows.prefix(30)))
    }

    func handle(_ action: HotkeyTap.Action) {
        switch action {
        case .begin(let reverse): begin(reverse: reverse)
        case .next: session == nil ? begin(reverse: false) : step(1)
        case .previous: session == nil ? begin(reverse: true) : step(-1)
        case .commit: commit()
        case .cancel: end()
        }
    }

    private func begin(reverse: Bool) {
        guard !windows.isEmpty else { return }
        let list = windows
        session = list
        // Если активное приложение без окон (например, Finder на рабочем столе),
        // то «предыдущее» окно — это первое в списке.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let start = (list[0].pid == frontPID && !list[0].isMinimized) ? 1 : 0
        index = reverse ? list.count - 1 : min(start, list.count - 1)
        // Снимки обновляются в фоне; панель покажет кэш и подменит картинки по мере готовности.
        Previews.shared.refresh(Array(list.prefix(30)))

        showWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.show() }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showDelay, execute: work)
    }

    private func show() {
        guard let s = session else { return }
        // Страховка от «залипания»: если модификатор уже отпущен, а событие потерялось.
        if !CGEventSource.flagsState(.combinedSessionState).contains(modifier) {
            commit()
            return
        }
        panel.present(s, selected: index, previews: Previews.shared.enabled && Previews.shared.hasPermission)
    }

    private func step(_ d: Int) {
        guard let s = session, !s.isEmpty else { return }
        index = (index + d + s.count) % s.count
        if panel.isVisible { panel.select(index) }
    }

    private func commit() {
        guard let s = session, s.indices.contains(index) else { end(); return }
        let w = s[index]
        end()
        // Оптимистично обновляем порядок, не дожидаясь, пока приложение отреагирует.
        if let i = windows.firstIndex(where: { $0.id == w.id }) {
            windows.insert(windows.remove(at: i), at: 0)
        }
        WindowTracker.shared.markFocused(w.id)
        Activator.activate(w)
    }

    private func end() {
        session = nil
        showWork?.cancel()
        showWork = nil
        panel.orderOut(nil)
    }
}
