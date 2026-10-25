import AppKit

/// Depois de encaixar uma janela, oferece as outras pra ocupar o espaço que sobrou (o Snap Assist
/// do Windows). Ao escolher uma, oferece de novo enquanto ainda houver espaço livre.
final class SnapAssist {
    private unowned let manager: WindowManager
    private var panel: AssistPanel?
    private var pending: DispatchWorkItem?
    private var clickMonitor: Any?
    private var appObserver: NSObjectProtocol?

    init(manager: WindowManager) {
        self.manager = manager
    }

    func offer(on display: Display, after snapped: Window, delay: TimeInterval) {
        dismiss()
        let work = DispatchWorkItem { [weak self] in self?.show(on: display, after: snapped) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func dismiss() {
        pending?.cancel()
        pending = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        clickMonitor = nil
        appObserver = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.1; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
    }

    private func show(on display: Display, after snapped: Window) {
        let occupied = manager.snappedWindows(on: display)
        let free = Set(Cell.allCases).subtracting(occupied.flatMap { $0.zone.cells })
        guard let zone = SnapZone.toFill(free: free) else { return }
        let visible = Window.allVisible()
        guard !isFilled(zone.frame(in: display.visible), on: display, by: visible, except: snapped) else { return }
        let taken = Set(occupied.map(\.window.id))
        let candidates = visible.filter { !taken.contains($0.id) && $0.id != snapped.id }
        guard !candidates.isEmpty else { return }

        let frame = Display.flip(manager.frame(for: zone, on: display)).insetBy(dx: 8, dy: 8)
        let panel = AssistPanel(frame: frame, windows: candidates)
        panel.onPick = { [weak self] window in
            guard let self else { return }
            self.dismiss()
            self.manager.snap(window, to: zone, on: display, assistDelay: 0.15)
            window.focus()
        }
        panel.onCancel = { [weak self] in
            self?.dismiss()
            snapped.focus()
        }
        self.panel = panel
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }

        // Clicar fora ou trocar de app fecha, como no Windows.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.dismiss() }
    }

    /// Se outra janela já ocupa o espaço (encaixada ou posta ali à mão), não há o que oferecer.
    /// Maximizadas não contam: estão atrás de tudo e cobririam qualquer espaço.
    private func isFilled(_ area: CGRect, on display: Display, by windows: [Window], except snapped: Window) -> Bool {
        let v = display.visible
        return windows.contains { window in
            guard window.id != snapped.id else { return false }
            let f = window.frame
            guard f.width < v.width - 200 || f.height < v.height - 200 else { return false }
            let covered = f.intersection(area)
            return !covered.isNull && covered.width * covered.height >= area.width * area.height * 0.8
        }
    }
}

final class AssistPanel: NSPanel {
    var onPick: ((Window) -> Void)?
    var onCancel: (() -> Void)?

    private let windows: [Window]
    private var cards: [AssistCard] = []
    private var columns = 1
    private var selected = 0 {
        didSet { cards.enumerated().forEach { $0.element.isSelected = $0.offset == selected } }
    }

    override var canBecomeKey: Bool { true }

    init(frame: CGRect, windows: [Window]) {
        self.windows = windows
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        buildContent()
    }

    private func buildContent() {
        let blur = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        contentView = blur

        let padding: CGFloat = 20, gap: CGFloat = 14, header: CGFloat = 44
        let cardSize = CGSize(width: 190, height: 130)

        let label = NSTextField(labelWithString: "Escolha uma janela para este espaço")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.frame = CGRect(x: padding, y: frame.height - header + 4, width: frame.width - padding * 2, height: 20)
        label.autoresizingMask = [.width, .minYMargin]
        blur.addSubview(label)

        let available = frame.width - padding * 2
        columns = max(1, Int((available + gap) / (cardSize.width + gap)))
        let rows = (windows.count + columns - 1) / columns
        let gridWidth = CGFloat(min(columns, windows.count)) * (cardSize.width + gap) - gap
        let gridHeight = CGFloat(rows) * (cardSize.height + gap) - gap

        let grid = FlippedView(frame: CGRect(x: 0, y: 0, width: available, height: gridHeight))
        let left = max(0, (available - gridWidth) / 2)
        for (index, window) in windows.enumerated() {
            let origin = CGPoint(x: left + CGFloat(index % columns) * (cardSize.width + gap),
                                 y: CGFloat(index / columns) * (cardSize.height + gap))
            let card = AssistCard(frame: CGRect(origin: origin, size: cardSize), window: window)
            card.onClick = { [weak self] in self?.onPick?(window) }
            card.onHover = { [weak self] in self?.selected = index }
            grid.addSubview(card)
            cards.append(card)
        }

        let viewport = CGRect(x: padding, y: padding, width: available, height: frame.height - header - padding)
        let scroll = NSScrollView(frame: viewport)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = gridHeight > viewport.height
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = grid
        // Poucas janelas: centraliza o grid na vertical em vez de grudar no topo.
        if gridHeight < viewport.height {
            scroll.frame = viewport.insetBy(dx: 0, dy: (viewport.height - gridHeight) / 2)
        }
        blur.addSubview(scroll)
        selected = 0
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: onCancel?()                                          // esc
        case 36, 76, 49: onPick?(windows[selected])                   // return, enter, espaço
        case 123: selected = max(0, selected - 1)                     // ←
        case 124: selected = min(cards.count - 1, selected + 1)       // →
        case 126: selected = max(0, selected - columns)               // ↑
        case 125: selected = min(cards.count - 1, selected + columns) // ↓
        default: super.keyDown(with: event)
        }
    }
}

private final class AssistCard: NSView {
    var onClick: (() -> Void)?
    var onHover: (() -> Void)?
    var isSelected = false { didSet { updateLayer() } }

    init(frame: CGRect, window: Window) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 2

        let app = window.app
        let icon = NSImageView(frame: CGRect(x: (frame.width - 56) / 2, y: frame.height - 16 - 56, width: 56, height: 56))
        icon.image = app?.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)

        let appName = app?.localizedName ?? ""
        let title = NSTextField(wrappingLabelWithString: window.title.isEmpty ? appName : window.title)
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.alignment = .center
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        title.frame = CGRect(x: 10, y: 22, width: frame.width - 20, height: 32)
        addSubview(title)

        let subtitle = NSTextField(labelWithString: window.title.isEmpty ? "" : appName)
        subtitle.font = .systemFont(ofSize: 10.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.frame = CGRect(x: 10, y: 6, width: frame.width - 20, height: 15)
        addSubview(subtitle)

        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let accent = NSColor.controlAccentColor
        layer?.backgroundColor = (isSelected ? accent.withAlphaComponent(0.3) : NSColor.white.withAlphaComponent(0.06)).cgColor
        layer?.borderColor = (isSelected ? accent : .clear).cgColor
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
