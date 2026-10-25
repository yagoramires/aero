import AeroCore
import AppKit
import NeyKit

/// Aero dentro do NeyHub. Linka só AeroCore e NeyKit (nunca NeyKitApp).
final class AeroEntry: NSObject, NeyPlugin {
    private lazy var app = AeroApp(defaults: AppDefaults.forApp("local.aero"), hosted: true, version: Self.version)

    var contractVersion: Int { neyPluginContractVersion }

    func start(host: NeyHost) {
        app.onOpenPermissions = { host.openPermissions() }
        app.start()
    }

    func stop() { app.stop() }
    func setMenuBarVisible(_ visible: Bool) { app.setMenuBarVisible(visible) }
    func makeScreen() -> NSViewController? { nil }
    func makeSettings() -> NSViewController { app.makeSettings() }

    /// Versão do manifest.json ao lado do dylib (o release.sh grava nele a do Info.plist).
    private static var version: String {
        var info = Dl_info()
        guard dladdr(#dsohandle, &info) != 0, let path = info.dli_fname else { return "?" }
        let manifest = URL(fileURLWithPath: String(cString: path)).deletingLastPathComponent().appendingPathComponent("manifest.json")
        return (try? JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: manifest)))?.version ?? "?"
    }
}

@_cdecl("neyhub_plugin_v1") public func neyhubPluginV1() -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(AeroEntry()).toOpaque()
}
