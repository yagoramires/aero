import Foundation

/// Registro em /tmp/aero-debug.log, só com o modo debug ligado (ver scripts/debug.sh).
func debugLog(_ message: @autoclosure () -> String) {
    guard UserDefaults.standard.bool(forKey: "debugBridge") else { return }
    let line = "\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(message())\n"
    let url = URL(fileURLWithPath: "/tmp/aero-debug.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}
