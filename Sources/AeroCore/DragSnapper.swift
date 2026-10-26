import AppKit

/// Observa o mouse do sistema inteiro: quando o usuário arrasta uma janela pela barra de título
/// até a borda da tela, mostra a prévia e encaixa ao soltar.
final class DragSnapper {
    private let manager: WindowManager
    private let preview = SnapPreview()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchdog: Timer?

    private enum State {
        case idle
        /// Botão pressionado; ainda não sabemos se é um arraste de janela.
        case pressed
        /// Arrastando algo; esperando a janela se mexer pra confirmar que é a barra de título.
        case candidate(Window, CGRect)
        case moving(Window)
        case ignoring
    }

    private var state = State.idle
    private var target: (zone: SnapZone, display: Display)?
    /// Quadrantes livres por monitor, calculados uma vez por arraste (a lista de janelas é cara).
    private var freeCells: [CGDirectDisplayID: Set<Cell>] = [:]

    init(manager: WindowManager) {
        self.manager = manager
    }

    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if let refcon {
                    Unmanaged<DragSnapper>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        // O macOS às vezes desliga o tap sem mandar o evento de aviso; confere de tempos em tempos.
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let tap = self?.tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
            debugLog("tap estava desligado; religando")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return true
    }

    /// Desinstalado no NeyHub: solta o event tap na hora.
    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        preview.hide()
        state = .idle
        target = nil
    }

    var isEnabled: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        let point = event.location
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            debugLog("tap desligado pelo sistema (\(type.rawValue)); religando")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .leftMouseDown:
            finish()
            state = .pressed

        case .leftMouseDragged:
            switch state {
            case .pressed:
                // Só consulta a Acessibilidade no primeiro movimento, pra cliques não custarem nada.
                guard let window = Window.at(point), window.pid != getpid() else {
                    debugLog("arraste em \(point): nenhuma janela sob o cursor")
                    state = .ignoring
                    return
                }
                debugLog("arraste em \(point): janela \(window.id) \(window.app?.localizedName ?? "?") frame=\(window.frame)")
                state = .candidate(window, window.frame)
            case let .candidate(window, start):
                let frame = window.frame
                if frame.size != start.size {
                    debugLog("tamanho mudou \(start.size) → \(frame.size): é resize")
                    state = .ignoring  // está redimensionando, não movendo
                } else if frame.origin != start.origin {
                    debugLog("movendo janela \(window.id)")
                    state = .moving(window)
                    manager.assist.dismiss()
                    manager.dragBegan(window, cursor: point)
                    update(point, dragging: window)
                }
                // Se nada mudou, segue conferindo até soltar: arrastar texto ou arquivo também
                // passa por aqui, e a consulta ao WindowServer é barata.
            case let .moving(window):
                update(point, dragging: window)
            case .idle, .ignoring:
                break
            }

        case .leftMouseUp:
            if case .moving = state { debugLog("soltou em \(point), zona=\(target.map { "\($0.zone)" } ?? "nenhuma")") }
            if case let .moving(window) = state, let target {
                // Deixa o app terminar o arraste antes de reposicionar.
                DispatchQueue.main.async {
                    self.manager.snap(window, to: target.zone, on: target.display, assistDelay: 0.1)
                }
            }
            finish()

        default:
            break
        }
    }

    private func update(_ point: CGPoint, dragging window: Window) {
        // Só encaixa encostando na borda; com algo já encaixado, a borda leva pro espaço livre.
        let detected: (zone: SnapZone, display: Display)? = SnapZone.detect(at: point).map { zone, display in
            (SnapZone.fit(zone, at: point, in: display.visible, free: free(on: display, excluding: window)), display)
        }
        defer { target = detected }
        guard let detected else { return preview.hide() }
        // Só recalcula o espaço livre quando muda de zona; no meio da zona é a mesma prévia.
        if detected.zone != target?.zone || detected.display != target?.display {
            preview.show(manager.frame(for: detected.zone, on: detected.display, excluding: window.id))
        }
    }

    /// Quadrantes livres do monitor, sem contar a janela arrastada.
    private func free(on display: Display, excluding window: Window) -> Set<Cell> {
        if let free = freeCells[display.id] { return free }
        let taken = manager.snappedWindows(on: display).filter { $0.window.id != window.id }.flatMap { $0.zone.cells }
        let free = Set(Cell.allCases).subtracting(taken)
        freeCells[display.id] = free
        return free
    }

    private func finish() {
        state = .idle
        target = nil
        freeCells = [:]
        preview.hide()
    }
}

/// Retângulo translúcido que mostra onde a janela vai parar.
final class SnapPreview {
    private let panel: NSPanel
    private var shownFrame: CGRect?
    /// Muda a cada show/hide: o fim de um fade-out antigo não pode esconder uma prévia nova.
    private var generation = 0

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        // Igual à prévia do encaixe nativo do macOS: vidro cinza translúcido, sem cor de destaque.
        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.25).cgColor
        tint.autoresizingMask = [.width, .height]
        blur.addSubview(tint)
        panel.contentView = blur
    }

    /// `frame` em coordenadas de cima pra baixo.
    func show(_ frame: CGRect) {
        guard frame != shownFrame else { return }
        generation += 1
        let target = Display.flip(frame).insetBy(dx: 6, dy: 6)
        if shownFrame == nil {
            panel.setFrame(target, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        shownFrame = frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard shownFrame != nil else { return }
        shownFrame = nil
        generation += 1
        let hiding = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == hiding else { return }
            self.panel.orderOut(nil)
        })
    }
}
