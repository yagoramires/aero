import AppKit
import ApplicationServices

/// Guarda quais janelas estão encaixadas e o tamanho que tinham antes, e aplica os encaixes
/// vindos do arraste, dos atalhos e do Snap Assist.
final class WindowManager {
    struct Snapped {
        let window: Window
        var zone: SnapZone
        /// Frame de antes do primeiro encaixe; é pra ele que a janela volta ao desencaixar.
        let restore: CGRect
        /// Último frame conhecido; mantido em dia pelo resize compartilhado.
        var frame: CGRect
    }

    private(set) var snapped: [CGWindowID: Snapped] = [:] { didSet { scheduleSave() } }
    /// Encaixes salvos de janelas que não estavam visíveis quando o app abriu (outro Space,
    /// minimizadas). Voltam a valer quando a janela aparece no mesmo lugar.
    private var dormant: [String: [String: String]] = [:]
    private var pendingSave: DispatchWorkItem?
    private var observers: [pid_t: AXObserver] = [:]
    /// Janelas que nós mesmos acabamos de mexer: a notificação de resize delas é eco, não usuário.
    private var echoes: [CGWindowID: Date] = [:]
    private var settles: [CGWindowID: DispatchWorkItem] = [:]
    private var dragged: [CGWindowID: (size: CGSize, date: Date)] = [:]
    private(set) lazy var assist = SnapAssist(manager: self)

    // MARK: Encaixar e desencaixar

    func snap(_ window: Window, to zone: SnapZone, on display: Display, assistDelay: TimeInterval? = nil) {
        revive(window)
        let restore = snapped[window.id]?.restore ?? draggedRestore(of: window) ?? window.frame
        let (target, neighbors) = fit(zone, on: display, excluding: window.id)
        adopt(neighbors, on: display)
        apply(window, target)
        // Guarda o destino, não o frame lido: o app pode levar alguns ms pra aplicar. Se ele não
        // aceitar o tamanho (mínimo, colunas do Terminal), a notificação de resize corrige.
        snapped[window.id] = Snapped(window: window, zone: zone, restore: restore, frame: target)
        observe(window)
        if let assistDelay { assist.offer(on: display, after: window, delay: assistDelay) }
    }

    /// Espaço da zona descontando as janelas que já ocupam o lado oposto da tela: com o Chrome
    /// na esquerda até 1331px, a direita vai de 1331 até a borda. Olha as janelas visíveis (não só
    /// as encaixadas pelo Aero): o que vale é o que está na tela.
    func frame(for zone: SnapZone, on display: Display, excluding id: CGWindowID? = nil) -> CGRect {
        fit(zone, on: display, excluding: id).frame
    }

    /// `frame(for:)` junto com as janelas cujas bordas delimitaram o espaço.
    private func fit(_ zone: SnapZone, on display: Display, excluding id: CGWindowID?) -> (frame: CGRect, neighbors: [Window]) {
        let zoneFrame = zone.frame(in: display.visible)
        guard zone != .maximize else { return (zoneFrame, []) }
        let v = display.visible, edge: CGFloat = 12, room: CGFloat = 200
        // Bordas das janelas encostadas em cada lado da tela; a zona vai até a mais próxima.
        var lefts: [(CGFloat, Window)] = [], rights: [(CGFloat, Window)] = []
        var tops: [(CGFloat, Window)] = [], bottoms: [(CGFloat, Window)] = []
        let frames = Window.visibleFrames(), displays = Display.all
        for window in Window.allVisible() where window.id != id {
            guard let f = frames[window.id], Display.best(for: f, among: displays) == display else { continue }
            // Só conta quem acompanha a zona quase inteira (não uma janelinha solta no canto) e
            // deixa espaço sobrando (não uma maximizada).
            if f.verticalOverlap(zoneFrame) >= zoneFrame.height * 0.6 {
                if f.minX <= v.minX + edge, f.midX < zoneFrame.midX, f.maxX <= v.maxX - room { lefts.append((f.maxX, window)) }
                if f.maxX >= v.maxX - edge, f.midX > zoneFrame.midX, f.minX >= v.minX + room { rights.append((f.minX, window)) }
            }
            if f.horizontalOverlap(zoneFrame) >= zoneFrame.width * 0.6 {
                if f.minY <= v.minY + edge, f.midY < zoneFrame.midY, f.maxY <= v.maxY - room { tops.append((f.maxY, window)) }
                if f.maxY >= v.maxY - edge, f.midY > zoneFrame.midY, f.minY >= v.minY + room { bottoms.append((f.minY, window)) }
            }
        }
        let left = lefts.max { $0.0 < $1.0 }, right = rights.min { $0.0 < $1.0 }
        let top = tops.max { $0.0 < $1.0 }, bottom = bottoms.min { $0.0 < $1.0 }
        let fitted = CGRect(x: left?.0 ?? zoneFrame.minX, y: top?.0 ?? zoneFrame.minY,
                            width: (right?.0 ?? zoneFrame.maxX) - (left?.0 ?? zoneFrame.minX),
                            height: (bottom?.0 ?? zoneFrame.maxY) - (top?.0 ?? zoneFrame.minY))
        guard fitted.width >= room && fitted.height >= 150 else { return (zoneFrame, []) }
        return (fitted, [left, right, top, bottom].compactMap { $0?.1 })
    }

    /// Desencaixa e devolve o tamanho e a posição originais, no monitor onde a janela está.
    /// Retorna false se não havia pra onde voltar (janela adotada, que já estava ali).
    @discardableResult
    func restore(_ window: Window) -> Bool {
        guard let s = forget(window.id, "restaurada") else { return false }
        let display = Display.best(for: window.frame)
        var target = s.restore
        if Display.best(for: target) != display {
            target.size.width = min(target.width, display.visible.width)
            target.size.height = min(target.height, display.visible.height)
            target.origin = CGPoint(x: display.visible.midX - target.width / 2,
                                    y: display.visible.midY - target.height / 2)
        }
        guard !target.isClose(to: window.frame, tolerance: 2) else { return false }
        apply(window, target)
        return true
    }

    /// Chamado quando o usuário começa a arrastar uma janela. Se estava encaixada, ela volta ao
    /// tamanho original na hora, mantendo o cursor no mesmo ponto proporcional da barra de título.
    func dragBegan(_ window: Window, cursor: CGPoint) {
        revive(window)
        guard let s = forget(window.id, "arrastada") else { return }
        let current = window.frame
        let ratio = current.width > 0 ? (cursor.x - current.minX) / current.width : 0.5
        echoes[window.id] = Date()
        dragged[window.id] = (s.restore.size, Date())
        window.setSize(s.restore.size)
        window.setPosition(CGPoint(x: (cursor.x - ratio * s.restore.width).rounded(), y: current.minY))
    }

    /// Tamanho original de uma janela desencaixada por arraste há pouco. O app leva alguns ms pra
    /// aplicar o tamanho devolvido; se ela for encaixada de novo nesse meio tempo, ler o frame
    /// guardaria o tamanho encaixado como se fosse o original.
    private func draggedRestore(of window: Window) -> CGRect? {
        guard let (size, date) = dragged.removeValue(forKey: window.id),
              Date().timeIntervalSince(date) < 10 else { return nil }
        return CGRect(origin: window.frame.origin, size: size)
    }

    /// Janelas que já estavam na tela e delimitam o espaço do encaixe passam a contar como
    /// encaixadas, pra divisória entre elas puxar as duas.
    private func adopt(_ windows: [Window], on display: Display) {
        for window in windows where snapped[window.id] == nil {
            let frame = window.frame
            let zone = SnapZone.closest(to: frame, in: display.visible)
            snapped[window.id] = Snapped(window: window, zone: zone, restore: frame, frame: frame)
            observe(window)
            debugLog("adotou \(window.id) \(window.app?.localizedName ?? "?") como \(zone)")
        }
    }

    /// Estado de encaixe confiável: se a janela saiu do lugar por outro meio, esquece.
    func state(of window: Window) -> Snapped? {
        revive(window)
        guard let s = snapped[window.id] else { return nil }
        guard window.frame.isClose(to: s.frame, tolerance: 40) else {
            forget(window.id, "saiu do lugar: \(window.frame) ≠ \(s.frame)")
            return nil
        }
        return s
    }

    /// Janelas encaixadas que ainda existem nesse monitor.
    func snappedWindows(on display: Display) -> [Snapped] {
        for (id, s) in snapped where !s.window.isAlive { forget(id, "janela não existe mais") }
        return snapped.values.filter { Display.best(for: $0.frame) == display }
    }

    @discardableResult
    private func forget(_ id: CGWindowID, _ reason: String) -> Snapped? {
        guard let s = snapped.removeValue(forKey: id) else { return nil }
        debugLog("esqueceu encaixe de \(id): \(reason)")
        unobserve(s.window)
        return s
    }

    private func apply(_ window: Window, _ rect: CGRect) {
        echoes[window.id] = Date()
        window.setFrame(rect)
    }

    // MARK: Persistência

    /// Salva os encaixes pra sobreviverem a um reinício do app; os IDs de janela continuam valendo
    /// enquanto as janelas existirem. Agrupado: um resize ao vivo mexe no estado dezenas de vezes
    /// por segundo.
    private func scheduleSave() {
        pendingSave?.cancel()
        let save = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: save)
    }

    private func save() {
        let entries = snapped.reduce(into: dormant) { result, entry in
            result[String(entry.key)] = ["zone": entry.value.zone.rawValue,
                                         "restore": NSStringFromRect(entry.value.restore),
                                         "frame": NSStringFromRect(entry.value.frame)]
        }
        UserDefaults.standard.set(entries, forKey: "snapped")
    }

    func load() {
        guard let saved = UserDefaults.standard.dictionary(forKey: "snapped") as? [String: [String: String]] else { return }
        // Descarta janelas que não existem mais; as que existem mas não estão visíveis agora
        // ficam adormecidas.
        let existing = Set((CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        dormant = saved.filter { CGWindowID($0.key).map(existing.contains) ?? false }
        for window in Window.allVisible() { revive(window) }
    }

    /// Reativa o encaixe salvo de uma janela, se ela continua no lugar onde estava encaixada.
    private func revive(_ window: Window) {
        guard snapped[window.id] == nil, let entry = dormant.removeValue(forKey: String(window.id)),
              let zone = SnapZone(rawValue: entry["zone"] ?? ""),
              let restore = entry["restore"].map(NSRectFromString),
              let frame = entry["frame"].map(NSRectFromString),
              window.frame.isClose(to: frame, tolerance: 40) else { return }
        snapped[window.id] = Snapped(window: window, zone: zone, restore: restore, frame: window.frame)
        observe(window)
    }

    // MARK: Atalhos (⌘ + setas), mesma lógica do Win + setas

    func handle(_ direction: Direction) {
        guard let window = Window.focused() else { return NSSound.beep() }
        let display = Display.best(for: window.frame)
        let zone = state(of: window)?.zone
        let snap = { (z: SnapZone, d: Display) in self.snap(window, to: z, on: d, assistDelay: 0.45) }

        switch direction {
        case .left:
            switch zone {
            case nil, .maximize: snap(.left, display)
            case .right: if !restore(window) { snap(.left, display) }
            case .topRight: snap(.topLeft, display)
            case .bottomRight: snap(.bottomLeft, display)
            // Já na esquerda: passa pra direita do monitor ao lado, como no Windows.
            case .left: display.neighbor(.left).map { snap(.right, $0) }
            case .topLeft: display.neighbor(.left).map { snap(.topRight, $0) }
            case .bottomLeft: display.neighbor(.left).map { snap(.bottomRight, $0) }
            }
        case .right:
            switch zone {
            case nil, .maximize: snap(.right, display)
            case .left: if !restore(window) { snap(.right, display) }
            case .topLeft: snap(.topRight, display)
            case .bottomLeft: snap(.bottomRight, display)
            case .right: display.neighbor(.right).map { snap(.left, $0) }
            case .topRight: display.neighbor(.right).map { snap(.topLeft, $0) }
            case .bottomRight: display.neighbor(.right).map { snap(.bottomLeft, $0) }
            }
        case .up:
            switch zone {
            case nil, .topLeft, .topRight: snap(.maximize, display)
            case .left: snap(.topLeft, display)
            case .right: snap(.topRight, display)
            case .bottomLeft: snap(.left, display)
            case .bottomRight: snap(.right, display)
            case .maximize: break
            }
        case .down:
            switch zone {
            case .maximize: restore(window)
            case .left: snap(.bottomLeft, display)
            case .right: snap(.bottomRight, display)
            case .topLeft: snap(.left, display)
            case .topRight: snap(.right, display)
            case nil, .bottomLeft, .bottomRight:
                forget(window.id, "minimizada")
                window.minimize()
            }
        }
    }

    /// ⌘⇧ + setas: leva a janela pro monitor vizinho, mantendo o encaixe ou a posição relativa.
    func moveToDisplay(_ direction: Direction) {
        guard let window = Window.focused() else { return NSSound.beep() }
        let from = Display.best(for: window.frame)
        guard let to = from.neighbor(direction, wrap: true) else { return }
        if let zone = state(of: window)?.zone {
            snap(window, to: zone, on: to)
            return
        }
        let f = window.frame, a = from.visible, b = to.visible
        let width = min(f.width, b.width), height = min(f.height, b.height)
        // Posição relativa no monitor de origem (0 = encostada à esquerda/topo, 1 = à direita/base).
        // Janela maior que o monitor de origem não tem folga pra medir: vai pro centro.
        func ratio(_ offset: CGFloat, _ slack: CGFloat) -> CGFloat {
            slack > 0 ? min(max(offset / slack, 0), 1) : 0.5
        }
        let x = b.minX + ratio(f.minX - a.minX, a.width - f.width) * (b.width - width)
        let y = b.minY + ratio(f.minY - a.minY, a.height - f.height) * (b.height - height)
        apply(window, CGRect(x: x.rounded(), y: y.rounded(), width: width, height: height))
    }

    // MARK: Resize compartilhado

    private func windowResized(_ window: Window) {
        guard var s = snapped[window.id] else { return }
        let old = s.frame, new = window.frame
        s.frame = new
        snapped[window.id] = s
        if let echo = echoes[window.id], Date().timeIntervalSince(echo) < 0.3 { return }
        guard new.size != old.size else { return }
        followEdge(of: window, from: old, to: new)

        // Os apps aplicam tamanho mínimo e arredondamentos com atraso; quando o resize assenta,
        // acerta as bordas com os frames reais.
        settles[window.id]?.cancel()
        let settle = DispatchWorkItem { [weak self] in self?.settleEdges(around: window) }
        settles[window.id] = settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: settle)
    }

    /// Durante o resize: quem encostava na borda que mudou vai junto.
    private func followEdge(of window: Window, from old: CGRect, to new: CGRect) {
        // Tolerância folgada porque apps como o Terminal arredondam o tamanho pra colunas inteiras.
        let tolerance: CGFloat = 24
        for (id, var other) in neighbors(of: window, display: Display.best(for: old)) {
            // Frame real, não o guardado: se o guardado estiver defasado, a conta sai absurda.
            let o = other.window.frame
            var f = o
            if new.maxX != old.maxX, abs(o.minX - old.maxX) < tolerance, o.verticalOverlap(old) > 50 {
                f = CGRect(x: new.maxX, y: o.minY, width: o.maxX - new.maxX, height: o.height)
            } else if new.minX != old.minX, abs(o.maxX - old.minX) < tolerance, o.verticalOverlap(old) > 50 {
                f.size.width = new.minX - o.minX
            } else if new.maxY != old.maxY, abs(o.minY - old.maxY) < tolerance, o.horizontalOverlap(old) > 50 {
                f = CGRect(x: o.minX, y: new.maxY, width: o.width, height: o.maxY - new.maxY)
            } else if new.minY != old.minY, abs(o.maxY - old.minY) < tolerance, o.horizontalOverlap(old) > 50 {
                f.size.height = new.minY - o.minY
            }
            guard f != o, f.width > 0, f.height > 0 else { continue }
            apply(other.window, f)
            other.frame = f
            snapped[id] = other
        }
    }

    /// Depois do resize: se ficou um vão, a vizinha estica; se ficou uma por cima da outra (a
    /// vizinha bateu no tamanho mínimo), é a janela redimensionada que recua até ela.
    private func settleEdges(around window: Window) {
        guard snapped[window.id] != nil else { return }
        let reach: CGFloat = 80
        var a = window.frame
        let original = a
        for (id, var other) in neighbors(of: window, display: Display.best(for: a)) {
            let b = other.window.frame
            var fixed = b
            if b.verticalOverlap(a) > 50, b.midX > a.midX, abs(b.minX - a.maxX) < reach {
                if b.minX > a.maxX { fixed = CGRect(x: a.maxX, y: b.minY, width: b.maxX - a.maxX, height: b.height) }
                else { a.size.width = b.minX - a.minX }
            } else if b.verticalOverlap(a) > 50, b.midX < a.midX, abs(b.maxX - a.minX) < reach {
                if b.maxX < a.minX { fixed.size.width = a.minX - b.minX }
                else { a = CGRect(x: b.maxX, y: a.minY, width: a.maxX - b.maxX, height: a.height) }
            } else if b.horizontalOverlap(a) > 50, b.midY > a.midY, abs(b.minY - a.maxY) < reach {
                if b.minY > a.maxY { fixed = CGRect(x: b.minX, y: a.maxY, width: b.width, height: b.maxY - a.maxY) }
                else { a.size.height = b.minY - a.minY }
            } else if b.horizontalOverlap(a) > 50, b.midY < a.midY, abs(b.maxY - a.minY) < reach {
                if b.maxY < a.minY { fixed.size.height = a.minY - b.minY }
                else { a = CGRect(x: a.minX, y: b.maxY, width: a.width, height: a.maxY - b.maxY) }
            }
            if fixed != b { apply(other.window, fixed) }
            other.frame = fixed
            snapped[id] = other
        }
        if a != original { apply(window, a) }
        snapped[window.id]?.frame = a
    }

    private func neighbors(of window: Window, display: Display) -> [(CGWindowID, Snapped)] {
        let displays = Display.all
        return snapped.filter { $0.key != window.id && Display.best(for: $0.value.window.frame, among: displays) == display }
            .map { ($0.key, $0.value) }
    }

    private func windowDestroyed(_ element: AXUIElement) {
        if let s = snapped.values.first(where: { CFEqual($0.window.element, element) }) {
            forget(s.window.id, "janela fechada")
        }
    }

    // MARK: Observadores de Acessibilidade

    private func observe(_ window: Window) {
        guard let observer = observer(for: window.pid) else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, window.element, kAXWindowResizedNotification as CFString, refcon)
        AXObserverAddNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString, refcon)
    }

    private func unobserve(_ window: Window) {
        guard let observer = observers[window.pid] else { return }
        AXObserverRemoveNotification(observer, window.element, kAXWindowResizedNotification as CFString)
        AXObserverRemoveNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString)
    }

    private func observer(for pid: pid_t) -> AXObserver? {
        if let observer = observers[pid] { return observer }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let manager = Unmanaged<WindowManager>.fromOpaque(refcon).takeUnretainedValue()
            if (notification as String) == kAXUIElementDestroyedNotification {
                manager.windowDestroyed(element)
            } else if let window = Window(element) {
                manager.windowResized(window)
            }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observers[pid] = created
        return created
    }
}
