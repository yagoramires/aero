import Combine
import NeyKit
import SwiftUI

/// Configurações (card no NeyHub, janela no avulso reaberto com ícone escondido). Só mostra estado: o Aero não tem ajustes.
struct SettingsView: View {
    let version: String
    /// nil hospedado: o ícone é do NeyHub.
    let menuBar: Bool?
    let trusted: () -> Bool
    let onMenuBar: (Bool) -> Void
    let act: (PopoverAction) -> Void
    @ViewState private var shown: Bool
    @ViewState private var granted: Bool

    init(version: String, menuBar: Bool?, trusted: @escaping () -> Bool, onMenuBar: @escaping (Bool) -> Void,
         act: @escaping (PopoverAction) -> Void) {
        self.version = version; self.menuBar = menuBar; self.trusted = trusted; self.onMenuBar = onMenuBar; self.act = act
        _shown = ViewState(wrappedValue: menuBar ?? true)
        _granted = ViewState(wrappedValue: trusted())
    }

    private static let shortcuts = [("Metade esquerda / direita", "⌘← ⌘→"), ("Maximizar / restaurar", "⌘↑ ⌘↓"),
                                    ("Mover de monitor", "⇧⌘ + setas")]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aero").font(.system(size: 16, weight: .bold)).foregroundStyle(Grafite.strong)
            Text("Encaixe de janelas estilo Windows · \(version)").font(.system(size: 12)).foregroundStyle(Grafite.muted)
                .padding(.bottom, 6)
            if menuBar != nil {
                GCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            title("Mostrar na barra de menus")
                            Spacer()
                            GSwitch(isOn: Binding(get: { shown }, set: { shown = $0; onMenuBar($0) }), label: "Mostrar na barra de menus")
                        }
                        Text("Escondido, o Aero continua funcionando: arrastar até a borda e os atalhos seguem valendo.")
                            .font(.system(size: 11)).foregroundStyle(Grafite.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            GCard {
                HStack {
                    title("Acessibilidade")
                    Spacer()
                    if granted {
                        Text("Concedida").font(.system(size: 11)).foregroundStyle(Grafite.accent)
                    } else {
                        Text("Não concedida").font(.system(size: 11)).foregroundStyle(Grafite.warn)
                        GPill(title: "Conceder") { act(.grant) }
                    }
                }
            }
            GCard {
                VStack(alignment: .leading, spacing: 0) {
                    title("Atalhos").padding(.bottom, 4)
                    ForEach(Self.shortcuts, id: \.0) { name, keys in
                        HStack {
                            Text(name).font(.system(size: 11))
                            Spacer()
                            Text(keys).font(.system(size: 11, design: .monospaced)).foregroundStyle(Grafite.accent)
                        }
                        .padding(.vertical, 4)
                        Rectangle().fill(Grafite.border).frame(height: 1)
                    }
                }
            }
            HStack(spacing: 6) {
                Chip(title: "Mostrar log de depuração") { act(.showLog) }
                Chip(title: "Reportar problema…") { act(.report) }
            }
        }
        .padding(18)
        .frame(minWidth: 420, maxWidth: 520, alignment: .leading)
        .grafiteWindow()
        // A permissão chega pelos Ajustes com a tela aberta.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in granted = trusted() }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Grafite.strong)
    }
}
