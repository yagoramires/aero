import NeyKit
import SwiftUI

/// shortcut: placeholder até o mockup das configurações ser aprovado (Task 12b troca por a tela de verdade).
struct SettingsView: View {
    var body: some View {
        Text("Configurações do Aero")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Grafite.strong)
            .frame(minWidth: 320, minHeight: 120)
            .grafiteWindow()
    }
}
