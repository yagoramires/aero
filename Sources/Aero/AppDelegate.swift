import AeroCore
import AppKit
import NeyKit
import NeyKitApp

/// Casca do avulso: o Aero em si mora no AeroCore, o mesmo que o NeyHub carrega como plugin.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var aero: AeroApp?
    private var updater: Updater?
    private var settings: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if HubCheck.isHosted(id: "local.aero") && HubCheck.leaveForHub(id: "local.aero", name: "Aero") { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let aero = AeroApp(defaults: .standard, hosted: false, version: version)
        aero.start()
        aero.setMenuBarVisible(Presence.load(.standard, hasScreen: false).menuBar)
        self.aero = aero

        let updater = Updater(name: "Aero", repo: "yagoramires/aero", id: "local.aero")
        aero.updateReady = updater.staged != nil
        updater.onChange = { [weak aero, weak updater] in aero?.updateReady = updater?.staged != nil }
        updater.start()
        self.updater = updater
        // Toda abertura: mostra as novidades uma vez e limpa um preparado velho.
        if let notes = Updater.notesAfterUpdate(id: "local.aero", current: version) {
            WhatsNew.show(name: "Aero", version: version, notes: notes)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = updater?.applyStaged()
    }

    /// Aberto de novo pelo Finder com o ícone escondido: único jeito de chegar às configurações.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let aero, !Presence.load(.standard, hasScreen: false).menuBar else { return true }
        if settings == nil {
            let window = NSWindow(contentViewController: aero.makeSettings())
            window.title = "Aero"
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            settings = window
        }
        settings?.center()
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
        return false
    }
}
