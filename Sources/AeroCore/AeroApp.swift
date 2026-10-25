import AppKit
import Carbon
import NeyKit
import ServiceManagement
import SwiftUI

/// O Aero inteiro, sem a casca: o avulso (`Aero`) e o plugin do NeyHub (`AeroPlugin`) usam o mesmo.
public final class AeroApp: NSObject {
    private let defaults: UserDefaults
    /// Dentro do NeyHub: sem pedir Acessibilidade, sem item de login e sem "Sair".
    private let hosted: Bool
    private let manager: WindowManager
    private lazy var drag = DragSnapper(manager: manager)
    let hotkeys = Hotkeys()
    private var statusItem: NSStatusItem?
    private var dragOK = false
    private var pendingHotkeys: [(key: Int, modifiers: Int, action: () -> Void)] = []
    private var timers: [Timer] = []
    private var debugObserver: NSObjectProtocol?
    private let popover = NSPopover()
    private var popoverHost: NSHostingController<PopoverView>?
    /// Janela em foco no clique do ícone: abrir o popover pode trocar o app em foco.
    private var target: Window?
    private var outsideClicks: Any?
    /// Hospedado: o NeyHub liga à tela de Permissões dele (a Acessibilidade é do NeyHub).
    public var onOpenPermissions: (() -> Void)?
    /// Avulso: o Updater já preparou uma versão, que entra quando o app fechar.
    public var updateReady = false

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
        dragOK = false
        manager.stop()
        if let debugObserver { DistributedNotificationCenter.default().removeObserver(debugObserver) }
        debugObserver = nil
        setMenuBarVisible(false)
        debugLog("parou")
    }

    /// false REMOVE o ícone; true cria com autosaveName "local.aero" (a posição na barra é lembrada).
    public func setMenuBarVisible(_ visible: Bool) {
        if !visible, let statusItem {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        } else if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "local.aero"
            item.button?.image = menuBarIcon()
            item.button?.target = self
            item.button?.action = #selector(togglePopover)
            statusItem = item
        }
    }

    public func makeSettings() -> NSViewController {
        NSHostingController(rootView: SettingsView(
            version: Log.version,
            menuBar: hosted ? nil : Presence.load(defaults, hasScreen: false).menuBar,
            trusted: { AXIsProcessTrusted() },
            onMenuBar: { [weak self] visible in self?.saveMenuBar(visible) },
            act: { [weak self] in self?.perform($0) }))
    }

    /// Avulso: no NeyHub quem guarda a presença é o NeyHub.
    private func saveMenuBar(_ visible: Bool) {
        var presence = Presence.load(defaults, hasScreen: false)
        presence.menuBar = visible
        presence.save(defaults)
        setMenuBarVisible(visible)
    }

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
        if popover.isShown { popoverHost?.rootView = popoverView() }
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
        if popover.isShown { popoverHost?.rootView = popoverView() }
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

// MARK: Popover da barra

extension AeroApp: NSPopoverDelegate {
    @objc private func togglePopover() {
        if popover.isShown { return popover.performClose(nil) }
        guard let button = statusItem?.button else { return }
        // Antes do show: o popover pode pegar o foco e aí a janela em foco seria a errada.
        target = Window.focused()
        if popoverHost == nil {
            let host = NSHostingController(rootView: popoverView())
            host.sizingOptions = .preferredContentSize
            popoverHost = host
            popover.contentViewController = host
            popover.behavior = .transient
            popover.appearance = NSAppearance(named: .darkAqua)
            popover.delegate = self
        } else {
            popoverHost?.rootView = popoverView()
        }
        // App de barra não é ativo: sem isso o primeiro clique no popover pode não chegar.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // O .transient sozinho não fecha quando o clique cai em outro app; um monitor global pega esse clique.
        if outsideClicks == nil {
            outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover.performClose(nil)
            }
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    public func popoverDidClose(_ notification: Notification) {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
    }

    /// O que o popover mostra para a janela `window` (a capturada no clique).
    func popoverState(for window: Window?) -> PopoverState {
        let from = window.map { Display.best(for: $0.frame) }
        let directions: [Direction] = [.up, .down, .left, .right]
        return PopoverState(version: Log.version, hosted: hosted, needsPermission: !dragOK,
                            hotkeysBusy: dragOK && !pendingHotkeys.isEmpty, hasWindow: window != nil,
                            neighbors: Set(directions.filter { from?.neighbor($0) != nil }), updateReady: updateReady,
                            loginItem: hosted ? nil : SMAppService.mainApp.status == .enabled)
    }

    private func popoverView() -> PopoverView {
        PopoverView(state: popoverState(for: target)) { [weak self] in self?.perform($0) }
    }

    func perform(_ action: PopoverAction) {
        let window = target
        if case .loginItem = action { return toggleLoginItem() }
        popover.performClose(nil)
        switch action {
        case .snap(let zone): manager.snapFocused(to: zone, window: window)
        case .restore: if let window { manager.restore(window) }
        case .move(let direction): manager.moveToDisplay(direction, window: window)
        case .grant: openAccessibilitySettings()
        case .showLog: showLog()
        case .report: reportProblem()
        case .quit: NSApp.terminate(nil)
        case .loginItem: break
        }
        // O popover ativou o Aero (ou o NeyHub): devolve o foco para a janela que foi mexida.
        switch action {
        case .snap, .restore, .move: window?.focus()
        default: break
        }
    }
}
