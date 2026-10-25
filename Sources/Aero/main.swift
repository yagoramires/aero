import AeroCore
import AppKit

if CommandLine.arguments.contains("--selftest") {
    // Sem NeyKitSelfTest.run(): ele confere AppDefaults.forApp("local.neyhub") === .standard e só passa dentro do NeyHub.
    AeroApp.selfTest()
    print("selftest ok")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
