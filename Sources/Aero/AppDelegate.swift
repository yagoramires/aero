import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = WindowManager()
    private lazy var drag = DragSnapper(manager: manager)
    private let hotkeys = Hotkeys()
    private var statusItem: NSStatusItem!
    private var dragOK = false
    private var pendingHotkeys: [(key: Int, modifiers: Int, action: () -> Void)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = menuBarIcon()
        rebuildMenu()

        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            start()
        } else {
            // A permissão é dada nos Ajustes do Sistema; começa sozinho assim que ela chegar.
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.start()
            }
        }
        setupDebugBridge()
    }

    private func start() {
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
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            self.retry()
            if self.dragOK && self.pendingHotkeys.isEmpty { timer.invalidate() }
        }
    }

    private func retry() {
        if !dragOK { dragOK = drag.start() }
        pendingHotkeys.removeAll { hotkeys.register($0.key, $0.modifiers, $0.action) }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        if !dragOK {
            menu.addItem(item("Dar permissão de Acessibilidade…", #selector(openAccessibilitySettings)))
        } else if !pendingHotkeys.isEmpty {
            menu.addItem(disabled("Atalhos em uso por outro app (Rectangle?)"))
        } else {
            menu.addItem(disabled("Aero ativo"))
        }
        menu.addItem(.separator())
        menu.addItem(disabled("Arraste até a borda ou o canto para encaixar"))
        menu.addItem(disabled("⌘ ← → ↑ ↓   Encaixar / restaurar"))
        menu.addItem(disabled("⌘⇧ ← → ↑ ↓   Mover para outro monitor"))
        menu.addItem(.separator())
        let login = item("Abrir ao iniciar sessão", #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Sair", #selector(NSApplication.terminate(_:)), key: "q"))
        statusItem.menu = menu
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

    @objc private func openAccessibilitySettings() {
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
        guard UserDefaults.standard.bool(forKey: "debugBridge") else { return }
        DistributedNotificationCenter.default().addObserver(
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
