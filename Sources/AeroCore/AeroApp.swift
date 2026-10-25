import AppKit
import Carbon
import ServiceManagement
import SwiftUI

/// O Aero inteiro, sem a casca: o avulso (`Aero`) e o plugin do NeyHub (`AeroPlugin`) usam o mesmo.
public final class AeroApp: NSObject {
    private let defaults: UserDefaults
    /// Dentro do NeyHub: sem pedir Acessibilidade, sem item de login e sem "Sair".
    private let hosted: Bool
    private let manager: WindowManager
    private lazy var drag = DragSnapper(manager: manager)
    private let hotkeys = Hotkeys()
    private var statusItem: NSStatusItem?
    private var dragOK = false
    private var pendingHotkeys: [(key: Int, modifiers: Int, action: () -> Void)] = []
    private var timers: [Timer] = []
    private var debugObserver: NSObjectProtocol?
    /// Hospedado: o NeyHub liga à tela de Permissões dele (a Acessibilidade é do NeyHub).
    public var onOpenPermissions: (() -> Void)?

    public init(defaults: UserDefaults, hosted: Bool, version: String) {
        self.defaults = defaults
        self.hosted = hosted
        manager = WindowManager(defaults: defaults)
        Log.version = version
    }

    public func start() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): !hosted] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            begin()
        } else {
            // A permissão é dada nos Ajustes do Sistema; começa sozinho assim que ela chegar.
            timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.begin()
            })
        }
        setupDebugBridge()

        debugLog("iniciou\n\(Log.environment)")
    }

    /// Desinstalar no NeyHub: o encaixe para na hora e o ícone sai.
    public func stop() {
        timers.forEach { $0.invalidate() }
        timers = []
        pendingHotkeys = []
        hotkeys.unregisterAll()
        drag.stop()
        manager.stop()
        if let debugObserver { DistributedNotificationCenter.default().removeObserver(debugObserver) }
        debugObserver = nil
        setMenuBarVisible(false)
        debugLog("parou")
    }

    /// false REMOVE o ícone; true cria com autosaveName "local.aero" (a posição na barra é lembrada).
    public func setMenuBarVisible(_ visible: Bool) {
        if !visible, let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        } else if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "local.aero"
            item.button?.image = menuBarIcon()
            statusItem = item
            rebuildMenu()
        }
    }

    public func makeSettings() -> NSViewController { NSHostingController(rootView: SettingsView()) }

    private func begin() {
        manager.load()
        let arrows = [(kVK_LeftArrow, Direction.left), (kVK_RightArrow, .right),
                      (kVK_UpArrow, .up), (kVK_DownArrow, .down)]
        pendingHotkeys = arrows.map { key, direction in
            (key, cmdKey, { [manager] in manager.handle(direction) })
        } + arrows.map { key, direction in
            (key, cmdKey | shiftKey, { [manager] in manager.moveToDisplay(direction) })
        }
        retry()
        // Se outro app (ex.: Rectangle) ainda segura algum atalho, ou o macOS demorou a liberar
        // o event tap depois da permissão, tenta de novo até conseguir.
        timers.append(Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            self.retry()
            if self.dragOK && self.pendingHotkeys.isEmpty { timer.invalidate() }
        })
    }

    private func retry() {
        if !dragOK {
            dragOK = drag.start()
            debugLog(dragOK ? "monitor do mouse ligado" : "monitor do mouse ainda não liberado pelo sistema")
        }
        let before = pendingHotkeys.count
        pendingHotkeys.removeAll { hotkeys.register($0.key, $0.modifiers, $0.action) }
        if pendingHotkeys.count != before || !pendingHotkeys.isEmpty {
            debugLog("atalhos: \(8 - pendingHotkeys.count) de 8 registrados")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    /// Versão monocromática do ícone do app: metade cheia, quadrante cheio e quadrante vazio.
    private func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            NSColor.black.set()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 7, height: 14), xRadius: 1.8, yRadius: 1.8).fill()
            NSBezierPath(roundedRect: NSRect(x: 10, y: 9, width: 7, height: 6), xRadius: 1.8, yRadius: 1.8).fill()
            let slot = NSBezierPath(roundedRect: NSRect(x: 10.65, y: 1.65, width: 5.7, height: 4.7), xRadius: 1.4, yRadius: 1.4)
            slot.lineWidth = 1.3
            slot.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Aero"
        return image
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func snapFocused(_ sender: NSMenuItem) {
        guard let zone = sender.representedObject as? String else { return }
        if zone == "restore" {
            if let window = Window.focused() { manager.restore(window) }
        } else if let zone = SnapZone(rawValue: zone) {
            manager.snapFocused(to: zone)
        }
    }

    @objc private func moveFocused(_ sender: NSMenuItem) {
        guard let direction = sender.representedObject as? Direction else { return }
        manager.moveToDisplay(direction)
    }

    @objc private func showLog() {
        debugLog("log aberto pelo menu\n\(Log.environment)")
        NSWorkspace.shared.activateFileViewerSelecting([Log.url])
    }

    /// Abre uma issue no GitHub já com o ambiente preenchido e mostra o log pra anexar.
    @objc private func reportProblem() {
        showLog()
        let body = """
        **O que aconteceu:**


        **O que você esperava:**


        **Ambiente:**
        \(Log.environment)

        _Arraste o arquivo aero.log (o Finder acabou de mostrar ele) pra cá._
        """
        var components = URLComponents(string: "https://github.com/yagoramires/aero/issues/new")!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    @objc private func openAccessibilitySettings() {
        if let onOpenPermissions { return onOpenPermissions() }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            try service.status == .enabled ? service.unregister() : service.register()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Não deu pra mudar a abertura ao iniciar sessão"
            alert.runModal()
        }
        // O macOS pode exigir aprovação manual em Ajustes → Geral → Itens de Início.
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        rebuildMenu()
    }

    /// Comandos de teste via scripts/debug.sh; só liga com
    /// `defaults write local.aero debugBridge -bool true`.
    private func setupDebugBridge() {
        guard defaults.bool(forKey: "debugBridge") else { return }
        debugObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("local.aero.debug"), object: nil, queue: .main
        ) { [weak self, manager] note in
            switch note.object as? String {
            case "left": manager.handle(.left)
            case "right": manager.handle(.right)
            case "up": manager.handle(.up)
            case "down": manager.handle(.down)
            case "screen-left": manager.moveToDisplay(.left)
            case "screen-right": manager.moveToDisplay(.right)
            case "screen-up": manager.moveToDisplay(.up)
            case "screen-down": manager.moveToDisplay(.down)
            case "dump":
                var lines = ["drag=\(self?.dragOK ?? false) tapEnabled=\(self?.drag.isEnabled ?? false) pendingHotkeys=\(self?.pendingHotkeys.count ?? -1) trusted=\(AXIsProcessTrusted())"]
                lines += Display.all.map { "display frame=\($0.frame) visible=\($0.visible)" }
                if let w = Window.focused() {
                    lines.append("focused \(w.id) \(w.app?.localizedName ?? "?") \"\(w.title)\" frame=\(w.frame)")
                }
                lines += Display.all.map { d in
                    "fit right=\(manager.frame(for: .right, on: d, excluding: Window.focused()?.id)) left=\(manager.frame(for: .left, on: d, excluding: Window.focused()?.id))"
                }
                lines += manager.snapped.values.map {
                    "snapped \($0.window.id) \($0.zone.rawValue) frame=\($0.frame) restore=\($0.restore)"
                }
                try? lines.joined(separator: "\n").write(toFile: "/tmp/aero-debug.txt", atomically: true, encoding: .utf8)
            default: break
            }
        }
    }
}

// MARK: Menu da barra

extension AeroApp: NSMenuDelegate {
    /// Montado a cada abertura, pra refletir a janela em foco e os monitores daquele momento.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !dragOK {
            menu.addItem(item("Dar permissão de Acessibilidade…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        } else if !pendingHotkeys.isEmpty {
            menu.addItem(disabled("Atalhos em uso por outro app (Rectangle?)"))
            menu.addItem(.separator())
        }

        let window = Window.focused()
        let positions: [(String, String, String?, CGRect)] = [
            ("Metade esquerda", SnapZone.left.rawValue, "←", CGRect(x: 0, y: 0, width: 0.5, height: 1)),
            ("Metade direita", SnapZone.right.rawValue, "→", CGRect(x: 0.5, y: 0, width: 0.5, height: 1)),
            ("Superior esquerdo", SnapZone.topLeft.rawValue, nil, CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
            ("Superior direito", SnapZone.topRight.rawValue, nil, CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
            ("Inferior esquerdo", SnapZone.bottomLeft.rawValue, nil, CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
            ("Inferior direito", SnapZone.bottomRight.rawValue, nil, CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
            ("Maximizar", SnapZone.maximize.rawValue, "↑", CGRect(x: 0, y: 0, width: 1, height: 1)),
            ("Restaurar", "restore", "↓", CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
        ]
        for (index, (title, zone, arrow, area)) in positions.enumerated() {
            if index == 2 || index == 6 { menu.addItem(.separator()) }
            let entry = NSMenuItem(title: title, action: window == nil ? nil : #selector(snapFocused(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = zone
            entry.image = layoutIcon(area)
            if let arrow { setArrowKey(entry, arrow, [.command]) }
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        let move = NSMenuItem(title: "Mover para outro monitor", action: nil, keyEquivalent: "")
        move.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)
        let submenu = NSMenu()
        let from = window.map { Display.best(for: $0.frame) }
        for (title, direction, arrow) in [("Acima", Direction.up, "↑"), ("Abaixo", .down, "↓"),
                                          ("À esquerda", .left, "←"), ("À direita", .right, "→")] {
            let available = from?.neighbor(direction) != nil
            let entry = NSMenuItem(title: title, action: available ? #selector(moveFocused(_:)) : nil, keyEquivalent: "")
            entry.target = self
            entry.representedObject = direction
            setArrowKey(entry, arrow, [.command, .shift])
            submenu.addItem(entry)
        }
        move.submenu = submenu
        move.isEnabled = Display.all.count > 1
        menu.addItem(move)

        menu.addItem(.separator())
        if !hosted {
            let login = item("Abrir ao iniciar sessão", #selector(toggleLoginItem))
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
        }

        let help = NSMenuItem(title: "Ajuda", action: nil, keyEquivalent: "")
        let helpMenu = NSMenu()
        helpMenu.addItem(disabled("Aero \(Log.version)"))
        helpMenu.addItem(.separator())
        helpMenu.addItem(item("Mostrar log de depuração", #selector(showLog)))
        helpMenu.addItem(item("Reportar problema…", #selector(reportProblem)))
        help.submenu = helpMenu
        menu.addItem(help)

        if !hosted {
            menu.addItem(.separator())
            menu.addItem(item("Sair", #selector(NSApplication.terminate(_:)), key: "q"))
        }
    }

    /// Mostra o atalho alinhado à direita, desenhado pelo sistema (⇧⌘ na ordem do macOS).
    private func setArrowKey(_ item: NSMenuItem, _ arrow: String, _ modifiers: NSEvent.ModifierFlags) {
        let keys: [String: Int] = ["←": NSLeftArrowFunctionKey, "→": NSRightArrowFunctionKey,
                                   "↑": NSUpArrowFunctionKey, "↓": NSDownArrowFunctionKey]
        guard let code = keys[arrow], let scalar = UnicodeScalar(code) else { return }
        item.keyEquivalent = String(Character(scalar))
        item.keyEquivalentModifierMask = modifiers
    }

    /// Desenho da tela com a área ocupada preenchida; `area` em frações, origem embaixo.
    private func layoutIcon(_ area: CGRect) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
            let screen = NSRect(x: 1.5, y: 1.5, width: 19, height: 13)
            let outline = NSBezierPath(roundedRect: screen, xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1.1
            NSColor.black.setStroke()
            outline.stroke()
            let inner = screen.insetBy(dx: 1.8, dy: 1.8)
            let fill = NSRect(x: inner.minX + area.minX * inner.width, y: inner.minY + area.minY * inner.height,
                              width: area.width * inner.width, height: area.height * inner.height)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: fill.insetBy(dx: 0.4, dy: 0.4), xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
