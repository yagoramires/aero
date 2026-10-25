import AeroCore
import AppKit
import NeyKit

/// Aero dentro do NeyHub. Linka só AeroCore e NeyKit (nunca NeyKitApp).
final class AeroEntry: NSObject, NeyPlugin {
    private lazy var app = AeroApp(defaults: AppDefaults.forApp("local.aero"), hosted: true, version: PluginLocation.version(dso: #dsohandle))

    var contractVersion: Int { neyPluginContractVersion }

    func start(host: NeyHost) {
        app.onOpenPermissions = { host.openPermissions() }
        app.start()
    }

    func stop() { app.stop() }
    func setMenuBarVisible(_ visible: Bool) { app.setMenuBarVisible(visible) }
    func makeScreen() -> NSViewController? { nil }
    func makeSettings() -> NSViewController { app.makeSettings() }
}

@_cdecl("neyhub_plugin_v1") public func neyhubPluginV1() -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(AeroEntry()).toOpaque()
}
