import AppKit

/// Registro de depuração em ~/Library/Logs/Aero/aero.log, sempre ligado. Só guarda as decisões
/// do app (que janela foi arrastada, qual zona, por que esqueceu um encaixe), nunca o conteúdo
/// das janelas. Serve pra quem tiver problema anexar no relato.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Aero/aero.log")
    /// Passou disso, o atual vira aero.log.1 e começa outro: no máximo ~4 MB em disco.
    private static let limit: UInt64 = 2_000_000
    private static var handle: FileHandle?
    /// Vem do `AeroApp.init`: no NeyHub o `Bundle.main` é o do NeyHub.
    static var version = "?"
    /// Desligado no --selftest e no --snapshots: não sujam o log de quem usa o Aero.
    static var enabled = true
    private static let clock: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func write(_ message: String) {
        guard enabled else { return }
        if handle == nil { open() }
        guard let handle else { return }
        handle.seekToEndOfFile()
        handle.write(Data("\(clock.string(from: Date())) \(message)\n".utf8))
        if handle.offsetInFile > limit { rotate() }
    }

    /// Versão, sistema e monitores: o que mais ajuda a entender um relato de problema.
    static var environment: String {
        let displays = Display.all.map { "\(Int($0.frame.width))×\(Int($0.frame.height)) em (\(Int($0.frame.minX)), \(Int($0.frame.minY)))" }
        return """
        Aero \(version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Monitores: \(displays.joined(separator: "; "))
        Acessibilidade: \(AXIsProcessTrusted() ? "permitida" : "sem permissão")
        """
    }

    private static func open() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
    }

    private static func rotate() {
        try? handle?.close()
        handle = nil
        let previous = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: url, to: previous)
    }
}

func debugLog(_ message: @autoclosure () -> String) {
    Log.write(message())
}
