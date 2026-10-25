import AppKit
import Carbon

/// `Aero --selftest`. Sem XCTest (só CommandLineTools). Nunca grava no `.standard`: é o domínio do Aero em uso.
extension AeroApp {
    public static func selfTest() {
        Log.enabled = false
        defaultsInjected()
        hotkeyFilter()
        popover()
        stopped()
        bottomEdge()
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
        // load() descarta ids de janelas que não existem: usa uma que existe e não está na tela (sempre há alguma no
        // WindowServer). Visível, o revive() a tiraria das adormecidas quando o app tem Acessibilidade.
        func ids(_ options: CGWindowListOption) -> [CGWindowID] {
            (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        }
        let onScreen = Set(ids(.optionOnScreenOnly))
        guard let id = ids(.optionAll).first(where: { !onScreen.contains($0) }).map(String.init) else { preconditionFailure("sem janela fora da tela no WindowServer") }
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

    /// Hospedado: sem "Abrir ao iniciar sessão" (é o login do NeyHub), sem "Sair" (fecharia o NeyHub) e sem
    /// a linha de atualização (quem atualiza é o NeyHub). Sem janela em foco os blocos ficam apagados.
    static func popover() {
        func state(hosted: Bool) -> PopoverState {
            let (d, name) = tempDefaults()
            defer { d.removePersistentDomain(forName: name) }
            let app = AeroApp(defaults: d, hosted: hosted, version: "9.8.7")
            app.updateReady = true
            return app.popoverState(for: nil)
        }
        let hosted = state(hosted: true), alone = state(hosted: false)
        precondition(!hosted.showsQuit && hosted.loginItem == nil && !hosted.showsUpdate && !hosted.showsSettings, "\(hosted)")
        precondition(alone.showsQuit && alone.loginItem != nil && alone.showsUpdate && alone.showsSettings, "\(alone)")
        precondition(hosted.version == "9.8.7" && alone.version == "9.8.7")
        precondition(!alone.hasWindow && alone.neighbors.isEmpty)
        // Sem start() o arrasto não foi liberado: mostra o pedido de permissão.
        precondition(alone.needsPermission && !alone.hotkeysBusy)

        // "Reiniciar agora" fica na linha de atualização (só avulso); hospedado a ação não chega à casca.
        for hosted in [true, false] {
            let (d, name) = tempDefaults()
            defer { d.removePersistentDomain(forName: name) }
            let app = AeroApp(defaults: d, hosted: hosted, version: "9.8.7")
            var relaunched = 0
            app.onRelaunch = { relaunched += 1 }
            app.perform(.relaunch)
            precondition(relaunched == (hosted ? 0 : 1), "Reiniciar agora hospedado=\(hosted): \(relaunched)")
        }
    }

    /// Desinstalar: depois do stop() nenhum atalho do Aero responde.
    static func stopped() {
        let (d, name) = tempDefaults()
        defer { d.removePersistentDomain(forName: name) }
        let app = AeroApp(defaults: d, hosted: true, version: "9.8.7")
        var hits = 0
        app.hotkeys.actions[1] = { hits += 1 }
        app.stop()
        precondition(app.hotkeys.actions.isEmpty)
        precondition(app.hotkeys.handle(EventHotKeyID(signature: Hotkeys.signature, id: 1)) == OSStatus(eventNotHandledErr) && hits == 0)
        precondition(app.popoverState(for: nil).needsPermission)
    }

    /// Borda de baixo: quadrante do lado do cursor; com outro monitor encostado embaixo, vale a faixa
    /// antes de o cursor atravessar (monitor de cima com o MacBook embaixo).
    static func bottomEdge() {
        let upper = Display(id: 2, frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080), visible: CGRect(x: 0, y: -1050, width: 1920, height: 1050))
        let lower = Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), visible: CGRect(x: 0, y: 30, width: 1920, height: 1050))
        let both = [lower, upper]
        func zone(_ x: CGFloat, _ y: CGFloat) -> SnapZone? { SnapZone.detect(at: CGPoint(x: x, y: y), among: both)?.0 }
        precondition(zone(1500, -2) == .bottomRight && zone(300, -6) == .bottomLeft, "borda encostada no monitor de baixo")
        precondition(zone(1500, -20) == nil, "longe da borda")
        precondition(zone(1000, 1079) == .bottomRight && zone(900, 1079) == .bottomLeft, "borda livre: lado do cursor")
        precondition(zone(1000, 1070) == nil, "borda livre só nos últimos px")
        precondition(zone(1919, -500) == .right && zone(0, -1000) == .topLeft, "laterais seguem iguais")
    }
}
