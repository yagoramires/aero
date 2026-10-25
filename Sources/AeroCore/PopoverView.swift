import NeyKit
import SwiftUI

/// O que o popover mostra, tirado no clique do ícone.
struct PopoverState {
    var version: String
    var hosted: Bool
    var needsPermission: Bool
    /// Outro app (Rectangle?) segura algum ⌘ + seta.
    var hotkeysBusy: Bool
    var hasWindow: Bool
    /// Direções com monitor vizinho, a partir do monitor da janela em foco.
    var neighbors: Set<Direction>
    var updateReady: Bool
    /// nil hospedado: o login é do NeyHub.
    var loginItem: Bool?

    var showsQuit: Bool { !hosted }
    /// Hospedado as configurações ficam no card do NeyHub.
    var showsSettings: Bool { !hosted }
    /// Hospedado quem atualiza é o NeyHub.
    var showsUpdate: Bool { updateReady && !hosted }
}

enum PopoverAction: Equatable { case snap(SnapZone), restore, move(Direction), grant, showLog, report, quit, loginItem, settings }

extension Grafite {
    // O Grafite não tem cor de alerta; estas vêm do mockup aprovado.
    static let warn = color(hex: "#ffb03d") ?? .orange
    static let warnBg = color(hex: "#2a2110") ?? .clear
    static let warnBorder = color(hex: "#5a4416") ?? .clear
}

struct PopoverView: View {
    let state: PopoverState
    let act: (PopoverAction) -> Void
    @ViewState private var help: Bool

    /// `help`: Ajuda já aberta (só o --snapshots usa).
    init(state: PopoverState, help: Bool = false, act: @escaping (PopoverAction) -> Void) {
        self.state = state; self.act = act
        _help = ViewState(wrappedValue: help)
    }

    private struct Tile { let short: String, title: String, action: PopoverAction, key: String, area: CGRect }
    private static let tiles = [
        Tile(short: "Esquerda", title: "Metade esquerda", action: .snap(.left), key: "⌘←", area: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
        Tile(short: "Direita", title: "Metade direita", action: .snap(.right), key: "⌘→", area: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)),
        Tile(short: "Maximizar", title: "Maximizar", action: .snap(.maximize), key: "⌘↑", area: CGRect(x: 0, y: 0, width: 1, height: 1)),
        Tile(short: "Restaurar", title: "Restaurar", action: .restore, key: "⌘↓", area: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
        Tile(short: "Sup. esq.", title: "Superior esquerdo", action: .snap(.topLeft), key: "", area: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
        Tile(short: "Sup. dir.", title: "Superior direito", action: .snap(.topRight), key: "", area: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
        Tile(short: "Inf. esq.", title: "Inferior esquerdo", action: .snap(.bottomLeft), key: "", area: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
        Tile(short: "Inf. dir.", title: "Inferior direito", action: .snap(.bottomRight), key: "", area: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
    ]
    private static let monitors: [(String, String, Direction, String)] = [
        ("↑ Acima", "Monitor acima", .up, "⇧⌘↑"), ("↓ Abaixo", "Monitor abaixo", .down, "⇧⌘↓"),
        ("← Esq.", "Monitor à esquerda", .left, "⇧⌘←"), ("→ Dir.", "Monitor à direita", .right, "⇧⌘→"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Aero").font(.system(size: 13, weight: .bold)).foregroundStyle(Grafite.strong)
                Text(state.version).font(.system(size: 10)).foregroundStyle(Grafite.muted)
                Spacer()
                Circle().fill(state.needsPermission ? Grafite.warn : Grafite.accent).frame(width: 7, height: 7)
                    .accessibilityLabel(state.needsPermission ? "Sem permissão" : "Funcionando")
            }
            .padding(.bottom, 10)

            if state.needsPermission { permission } else { snapping }
            if state.hotkeysBusy { line("Atalhos em uso por outro app (Rectangle?)", Grafite.warn) }
            if state.showsUpdate { line("Atualização pronta — entra ao sair", Grafite.accent) }
            if let on = state.loginItem {
                HStack {
                    Text("Abrir ao iniciar sessão").font(.system(size: 11))
                    Spacer()
                    GSwitch(isOn: Binding(get: { on }, set: { _ in act(.loginItem) }), label: "Abrir ao iniciar sessão")
                }
                .padding(.top, 8)
            }
            footer
        }
        .padding(12)
        .frame(width: 280)
        .grafiteWindow()
    }

    private var snapping: some View {
        VStack(alignment: .leading, spacing: 6) {
            GSectionLabel("Encaixar janela em foco")
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(Self.tiles[row * 4 ..< row * 4 + 4], id: \.title) { t in
                        Block(label: t.short, key: t.key, accessibility: t.title, enabled: state.hasWindow, icon: LayoutIcon(area: t.area)) { act(t.action) }
                    }
                }
            }
            GSectionLabel("Mover para outro monitor").padding(.top, 4)
            HStack(spacing: 6) {
                ForEach(Self.monitors, id: \.1) { label, title, direction, key in
                    Block(label: label, key: key, accessibility: title, enabled: state.hasWindow && state.neighbors.contains(direction),
                          icon: EmptyView()) { act(.move(direction)) }
                }
            }
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Precisa de Acessibilidade").font(.system(size: 12)).foregroundStyle(Grafite.warn)
                Spacer()
                GPill(title: "Conceder") { act(.grant) }
            }
            .padding(8)
            .background(Grafite.warnBg, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Grafite.warnBorder, lineWidth: 1))
            Text(state.hosted ? "Encaixes e atalhos voltam sozinhos assim que a permissão é dada. “Conceder” abre a tela de Permissões do NeyHub."
                              : "Encaixes e atalhos voltam sozinhos assim que a permissão é dada.")
                .font(.system(size: 11)).foregroundStyle(Grafite.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func line(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(color).padding(.top, 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Grafite.border).frame(height: 1).padding(.bottom, 4)
            HStack(spacing: 6) {
                Chip(title: help ? "Ajuda ▴" : "Ajuda ▾") { help.toggle() }
                Spacer()
                if state.showsQuit { Chip(title: "Sair") { act(.quit) } }
            }
            if help {
                Text("Aero \(state.version)").font(.system(size: 10)).foregroundStyle(Grafite.muted).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    if state.showsSettings { Chip(title: "Configurações…") { act(.settings) } }
                    Chip(title: "Mostrar log de depuração") { act(.showLog) }
                    Chip(title: "Reportar problema…") { act(.report) }
                }
            }
        }
        .padding(.top, 12)
    }
}

/// Bloco do popover: desenho (ou nada), rótulo e atalho. Apagado quando não dá pra usar.
private struct Block<Icon: View>: View {
    let label: String, key: String, accessibility: String, enabled: Bool, icon: Icon, action: () -> Void
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon
                Text(label).font(.system(size: 9)).foregroundStyle(Grafite.muted).lineLimit(1)
                Text(key).font(.system(size: 9, design: .monospaced)).foregroundStyle(Grafite.accent).frame(minHeight: 11)
            }
            .padding(.vertical, 6).padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .background(Grafite.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(hover && enabled ? Grafite.accent : Grafite.cardBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hover = $0 }
        .accessibilityLabel(accessibility)
    }
}

/// Desenho da tela com a área ocupada preenchida; `area` em frações, origem em cima.
struct LayoutIcon: View {
    let area: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3).stroke(Grafite.ghostBorder, lineWidth: 1)
            RoundedRectangle(cornerRadius: 2).fill(Grafite.accent)
                .frame(width: area.width * 30, height: area.height * 18)
                .offset(x: 2 + area.minX * 30, y: 2 + area.minY * 18)
        }
        .frame(width: 34, height: 22)
        .accessibilityHidden(true)
    }
}

/// Botão discreto do rodapé e das configurações (o ".g" do mockup).
struct Chip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 10)).foregroundStyle(Grafite.muted)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Grafite.card, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
