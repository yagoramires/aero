import AppKit

enum Direction {
    case left, right, up, down
}

/// Monitor, com retângulos em coordenadas globais de cima pra baixo: origem no canto superior
/// esquerdo do monitor principal, y crescendo pra baixo. É o sistema da API de Acessibilidade e
/// dos CGEvents; o Cocoa (origem embaixo) só aparece na hora de posicionar janelas nossas.
struct Display: Equatable {
    /// Identifica o monitor; frame e área visível mudam (Dock, barra de menu escondida), ele não.
    let id: CGDirectDisplayID
    let frame: CGRect
    let visible: CGRect

    static var all: [Display] {
        NSScreen.screens.map { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            return Display(id: id, frame: flip(screen.frame), visible: flip(screen.visibleFrame))
        }
    }

    static func == (a: Display, b: Display) -> Bool { a.id == b.id }

    /// Converte entre Cocoa e coordenadas de cima pra baixo; a conta é a mesma nos dois sentidos.
    static func flip(_ rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Monitor que contém a maior parte do retângulo (ou o mais próximo, se não contém nada).
    static func best(for rect: CGRect, among displays: [Display] = all) -> Display {
        let area = { (d: Display) -> CGFloat in
            let i = d.frame.intersection(rect)
            return i.isNull ? 0 : i.width * i.height
        }
        if let d = displays.max(by: { area($0) < area($1) }), area(d) > 0 { return d }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return displays.min { $0.distance(to: center) < $1.distance(to: center) }
            ?? Display(id: 0, frame: .zero, visible: .zero)
    }

    /// Monitor vizinho na direção. Só conta quem está de fato daquele lado (com faixa em comum no
    /// outro eixo), não um empilhado. Com `wrap`, dá a volta pro do outro extremo.
    func neighbor(_ direction: Direction, wrap: Bool = false) -> Display? {
        let horizontal = direction == .left || direction == .right
        let others = Display.all.filter {
            $0 != self && (horizontal ? $0.frame.verticalOverlap(frame) : $0.frame.horizontalOverlap(frame)) > 0
        }
        let position = { (d: Display) in horizontal ? d.frame.midX : d.frame.midY }
        let before = others.filter { position($0) < position(self) }.sorted { position($0) < position($1) }
        let after = others.filter { position($0) > position(self) }.sorted { position($0) < position($1) }
        // Em coordenadas de cima pra baixo, "antes" é à esquerda ou acima.
        switch direction {
        case .left, .up: return before.last ?? (wrap ? after.last : nil)
        case .right, .down: return after.first ?? (wrap ? before.first : nil)
        }
    }

    private func distance(to point: CGPoint) -> CGFloat {
        hypot(frame.midX - point.x, frame.midY - point.y)
    }
}

/// Quadrantes de um monitor; servem pra saber que parte da tela já está ocupada.
enum Cell: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

enum SnapZone: String {
    case left, right, maximize, topLeft, topRight, bottomLeft, bottomRight

    static let quarters: [SnapZone] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    var cells: Set<Cell> {
        switch self {
        case .maximize: return Set(Cell.allCases)
        case .left: return [.topLeft, .bottomLeft]
        case .right: return [.topRight, .bottomRight]
        case .topLeft: return [.topLeft]
        case .topRight: return [.topRight]
        case .bottomLeft: return [.bottomLeft]
        case .bottomRight: return [.bottomRight]
        }
    }

    func frame(in v: CGRect) -> CGRect {
        let w = (v.width / 2).rounded(.down), h = (v.height / 2).rounded(.down)
        let midX = v.minX + w, midY = v.minY + h
        switch self {
        case .maximize: return v
        case .left: return CGRect(x: v.minX, y: v.minY, width: w, height: v.height)
        case .right: return CGRect(x: midX, y: v.minY, width: v.width - w, height: v.height)
        case .topLeft: return CGRect(x: v.minX, y: v.minY, width: w, height: h)
        case .topRight: return CGRect(x: midX, y: v.minY, width: v.width - w, height: h)
        case .bottomLeft: return CGRect(x: v.minX, y: midY, width: w, height: v.height - h)
        case .bottomRight: return CGRect(x: midX, y: midY, width: v.width - w, height: v.height - h)
        }
    }

    /// Zona que mais se parece com um frame qualquer (maior sobreposição relativa).
    static func closest(to frame: CGRect, in visible: CGRect) -> SnapZone {
        let zones: [SnapZone] = [.left, .right] + quarters
        func score(_ zone: SnapZone) -> CGFloat {
            let z = zone.frame(in: visible), i = z.intersection(frame)
            guard !i.isNull else { return 0 }
            let shared = i.width * i.height
            return shared / (z.width * z.height + frame.width * frame.height - shared)
        }
        return zones.max { score($0) < score($1) } ?? .left
    }

    /// Próximo espaço que o Snap Assist deve oferecer: uma metade inteira livre, senão o
    /// primeiro quadrante livre.
    static func toFill(free: Set<Cell>) -> SnapZone? {
        guard !free.isEmpty, free.count < 4 else { return nil }
        return ([.left, .right] + quarters).first { free.isSuperset(of: $0.cells) }
    }

    /// Zona sob o cursor durante um arraste, quando ele encosta numa borda que não dá pra outro
    /// monitor (ou na barra de menu). Igual ao Windows: lateral = metade, canto = quadrante, topo = maximizar.
    static func detect(at p: CGPoint) -> (SnapZone, Display)? {
        let displays = Display.all
        guard let d = displays.first(where: { $0.frame.contains(p) }) else { return nil }
        let f = d.frame
        let edge: CGFloat = 3, corner: CGFloat = 100
        func open(_ x: CGFloat, _ y: CGFloat) -> Bool {
            !displays.contains { $0.frame.contains(CGPoint(x: x, y: y)) }
        }
        let atLeft = p.x <= f.minX + edge && open(f.minX - 1, p.y)
        let atRight = p.x >= f.maxX - 1 - edge && open(f.maxX + 1, p.y)
        // A faixa da barra de menu também conta como topo: com um monitor empilhado em cima, o
        // cursor passaria direto pra ele e nunca daria pra maximizar arrastando.
        let atTop = (p.y <= f.minY + edge && open(p.x, f.minY - 1)) || p.y < d.visible.minY
        let atBottom = p.y >= f.maxY - 1 - edge && open(p.x, f.maxY + 1)
        let nearTop = p.y < f.minY + corner, nearBottom = p.y > f.maxY - corner
        let nearLeft = p.x < f.minX + corner, nearRight = p.x > f.maxX - corner

        if atLeft { return (nearTop ? .topLeft : nearBottom ? .bottomLeft : .left, d) }
        if atRight { return (nearTop ? .topRight : nearBottom ? .bottomRight : .right, d) }
        if atTop { return (nearLeft ? .topLeft : nearRight ? .topRight : .maximize, d) }
        if atBottom && nearLeft { return (.bottomLeft, d) }
        if atBottom && nearRight { return (.bottomRight, d) }
        return nil
    }
}

extension CGRect {
    /// Quanto dois retângulos se sobrepõem no eixo vertical / horizontal.
    func verticalOverlap(_ other: CGRect) -> CGFloat { Swift.min(maxY, other.maxY) - Swift.max(minY, other.minY) }
    func horizontalOverlap(_ other: CGRect) -> CGFloat { Swift.min(maxX, other.maxX) - Swift.max(minX, other.minX) }

    func isClose(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
