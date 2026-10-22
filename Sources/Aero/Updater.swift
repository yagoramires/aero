import AppKit
import Security

/// Confere no GitHub se há versão nova e, se o usuário quiser, baixa, troca o próprio app e reabre.
final class Updater {
    struct Release {
        let version: String
        let page: URL
        let asset: URL?
    }

    enum Failure: LocalizedError {
        case unpack, signature

        var errorDescription: String? {
            switch self {
            case .unpack: return "O arquivo baixado não tem o Aero.app."
            case .signature: return "A versão baixada não foi assinada pelo mesmo certificado deste app."
            }
        }
    }

    static let releasesPage = URL(string: "https://github.com/yagoramires/aero/releases/latest")!
    private static let api = URL(string: "https://api.github.com/repos/yagoramires/aero/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Versão nova encontrada e ainda não instalada; o menu oferece atualizar.
    private(set) var available: Release?
    var onChange: (() -> Void)?

    /// `manual`: veio do menu, então também avisa quando não há nada novo ou quando falha.
    func check(manual: Bool) {
        var request = URLRequest(url: Self.api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Aero/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            let release = data.flatMap(Self.parse)
            DispatchQueue.main.async { self.finish(release, error: error, manual: manual) }
        }.resume()
    }

    /// Instala o último release sem comparar versões nem perguntar (teste do fluxo via debug).
    func installLatest() {
        var request = URLRequest(url: Self.api)
        request.setValue("Aero/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let release = data.flatMap(Self.parse) else { return }
            DispatchQueue.main.async { self.install(release) }
        }.resume()
    }

    func offer(_ release: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Aero \(release.version) disponível"
        alert.informativeText = "Você está na versão \(Self.currentVersion). A atualização leva alguns segundos e o Aero reabre sozinho."
        alert.addButton(withTitle: "Atualizar agora")
        alert.addButton(withTitle: "Ver novidades")
        alert.addButton(withTitle: "Depois")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return install(release)
        case .alertSecondButtonReturn: NSWorkspace.shared.open(release.page)
        default: break
        }
        // Não atualizou agora: não pergunta de novo por essa versão; o menu continua oferecendo.
        UserDefaults.standard.set(release.version, forKey: "postponedVersion")
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) where (i < x.count ? x[i] : 0) != (i < y.count ? y[i] : 0) {
            return (i < x.count ? x[i] : 0) > (i < y.count ? y[i] : 0)
        }
        return false
    }

    private static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        return Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "v")), page: page,
                       asset: (zip?["browser_download_url"] as? String).flatMap(URL.init(string:)))
    }

    private func finish(_ release: Release?, error: Error?, manual: Bool) {
        guard let release else {
            debugLog("update: não deu pra consultar (\(error?.localizedDescription ?? "resposta inesperada"))")
            if manual { Self.inform("Não deu pra buscar atualizações", "Verifique a conexão e tente de novo.") }
            return
        }
        let newer = Self.isNewer(release.version, than: Self.currentVersion)
        debugLog("update: instalada \(Self.currentVersion), última \(release.version)")
        available = newer ? release : nil
        onChange?()
        if newer && (manual || UserDefaults.standard.string(forKey: "postponedVersion") != release.version) {
            offer(release)
        } else if manual {
            Self.inform("Você está na versão mais recente", "Aero \(Self.currentVersion).")
        }
    }

    func install(_ release: Release) {
        guard let asset = release.asset else {
            NSWorkspace.shared.open(release.page)
            return
        }
        debugLog("update: baixando \(asset.absoluteString)")
        URLSession.shared.downloadTask(with: asset) { file, _, error in
            // O arquivo baixado some quando este bloco termina: descompacta aqui mesmo.
            let result = Result { () throws -> URL in
                guard let file else { throw error ?? URLError(.badServerResponse) }
                return try Self.unpack(file)
            }
            DispatchQueue.main.async { self.replace(with: result, release: release) }
        }.resume()
    }

    private static func unpack(_ zip: URL) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aero-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, folder.path]
        try ditto.run()
        ditto.waitUntilExit()
        let app = folder.appendingPathComponent("Aero.app")
        guard ditto.terminationStatus == 0, FileManager.default.fileExists(atPath: app.path) else { throw Failure.unpack }
        return app
    }

    private func replace(with result: Result<URL, Error>, release: Release) {
        do {
            let app = try result.get()
            guard Self.signedLikeMe(app) else { throw Failure.signature }
            let current = Bundle.main.bundleURL
            _ = try FileManager.default.replaceItemAt(current, withItemAt: app)
            debugLog("update: \(release.version) instalada em \(current.path); reabrindo")
            // Reabre depois que este processo sair.
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", current.path]
            try relaunch.run()
            NSApp.terminate(nil)
        } catch {
            debugLog("update: falhou (\(error.localizedDescription))")
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Não deu pra atualizar sozinho"
            alert.informativeText = "\(error.localizedDescription)\n\nBaixe a versão nova na página do release."
            alert.addButton(withTitle: "Abrir página")
            alert.addButton(withTitle: "Cancelar")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.page) }
        }
    }

    /// Só instala o que foi assinado pelo mesmo certificado do app em execução: o requisito
    /// designado inclui o identificador e o certificado, então um zip trocado no meio do
    /// caminho não passa.
    private static func signedLikeMe(_ app: URL) -> Bool {
        var me: SecCode?, myStatic: SecStaticCode?, requirement: SecRequirement?, candidate: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &myStatic) == errSecSuccess, let myStatic,
              SecCodeCopyDesignatedRequirement(myStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess, let candidate else { return false }
        return SecStaticCodeCheckValidity(candidate, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }

    private static func inform(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
