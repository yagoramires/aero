import AppKit
import Carbon

/// `Aero --selftest`. Sem XCTest (só CommandLineTools). Nunca grava no `.standard`: é o domínio do Aero em uso.
extension AeroApp {
    public static func selfTest() {
        defaultsInjected()
        hotkeyFilter()
        hostedMenu()
    }

    /// Suite temporária no lugar do `.standard`; o chamador apaga. Nome fixo: não junta um plist por rodada.
    private static func tempDefaults() -> (UserDefaults, String) {
        let name = "aero.selftest"
        return (UserDefaults(suiteName: name)!, name)
    }

    /// Encaixes salvos vão para o `defaults` injetado, nunca para o `.standard`.
    static func defaultsInjected() {
        let (d, name) = tempDefaults()
        defer { d.removePersistentDomain(forName: name) }
        // load() descarta ids de janelas que não existem: usa uma que existe (sempre há alguma no WindowServer).
        let ids = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        guard let id = ids.first.map(String.init) else { preconditionFailure("sem janelas no WindowServer") }
        // Frame que nenhuma janela real tem: a entrada fica adormecida, não encaixa nada.
        let sentinel = NSStringFromRect(NSRect(x: -77777, y: -77777, width: 3, height: 3))
        let entry = ["zone": SnapZone.left.rawValue, "restore": sentinel, "frame": sentinel]
        d.set([id: entry], forKey: "snapped")

        let manager = WindowManager(defaults: d)
        manager.load()
        d.removeObject(forKey: "snapped")
        manager.save()
        let saved = d.dictionary(forKey: "snapped") as? [String: [String: String]]
        precondition(saved?[id] == entry, "encaixe não voltou para o defaults injetado: \(String(describing: saved))")
        let standard = UserDefaults.standard.dictionary(forKey: "snapped") as? [String: [String: String]]
        precondition(standard?[id]?["frame"] != sentinel, "encaixe vazou para o .standard")
    }

    /// No NeyHub o alvo de eventos é de todos: atalho de outra assinatura segue para o próximo handler.
    static func hotkeyFilter() {
        let hotkeys = Hotkeys()
        var hits = 0
        hotkeys.actions[1] = { hits += 1 }
        let notHandled = OSStatus(eventNotHandledErr)
        precondition(hotkeys.handle(EventHotKeyID(signature: OSType(0x4E65_7948), id: 1)) == notHandled) // 'NeyH'
        precondition(hotkeys.handle(EventHotKeyID(signature: Hotkeys.signature, id: 2)) == notHandled)
        precondition(hits == 0)
        precondition(hotkeys.handle(EventHotKeyID(signature: Hotkeys.signature, id: 1)) == noErr && hits == 1)
    }

    /// Hospedado: sem "Abrir ao iniciar sessão" (é o login do NeyHub) nem "Sair" (fecharia o NeyHub); versão vem do init.
    static func hostedMenu() {
        func titles(hosted: Bool) -> [String] {
            let (d, name) = tempDefaults()
            defer { d.removePersistentDomain(forName: name) }
            let menu = NSMenu()
            AeroApp(defaults: d, hosted: hosted, version: "9.8.7").menuNeedsUpdate(menu)
            return menu.items.flatMap { [$0.title] + ($0.submenu?.items.map(\.title) ?? []) }
        }
        let hosted = titles(hosted: true), alone = titles(hosted: false)
        precondition(!hosted.contains("Abrir ao iniciar sessão") && !hosted.contains("Sair"), "\(hosted)")
        precondition(alone.contains("Abrir ao iniciar sessão") && alone.contains("Sair"), "\(alone)")
        precondition(hosted.contains("Aero 9.8.7") && alone.contains("Aero 9.8.7"))
        precondition(!(hosted + alone).contains { $0.contains("atualiza") }, "item de atualização ainda no menu")
    }
}
