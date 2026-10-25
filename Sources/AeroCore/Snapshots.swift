import AppKit
import SwiftUI

/// `Aero --snapshots <pasta>`: desenha o popover (com e sem permissão) e as configurações em PNG e sai.
public enum Snapshots {
    public static func run(into folder: URL) {
        Log.enabled = false
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sample = PopoverState(version: "0.5.0", hosted: false, needsPermission: false, hotkeysBusy: false, hasWindow: true,
                                  neighbors: [.up], updateReady: true, loginItem: true)
        save(PopoverView(state: sample) { _ in }, as: "aero-popover.png", in: folder)
        save(PopoverView(state: sample, help: true) { _ in }, as: "aero-popover-ajuda.png", in: folder)
        var blocked = sample
        blocked.needsPermission = true
        blocked.updateReady = false
        save(PopoverView(state: blocked) { _ in }, as: "aero-popover-sem-permissao.png", in: folder)
        var hosted = sample
        hosted.hosted = true
        hosted.loginItem = nil
        save(PopoverView(state: hosted) { _ in }, as: "aero-popover-neyhub.png", in: folder)
        save(SettingsView(version: "0.5.0", menuBar: true, trusted: { true }, onMenuBar: { _ in }, act: { _ in }).frame(width: 520),
             as: "aero-settings.png", in: folder)
        save(SettingsView(version: "0.5.0", menuBar: nil, trusted: { false }, onMenuBar: { _ in }, act: { _ in }).frame(width: 520),
             as: "aero-settings-neyhub.png", in: folder)
        print("ok \(folder.path)")
    }

    private static func save<V: View>(_ view: V, as name: String, in folder: URL) {
        MainActor.assumeIsolated {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("falhou \(name)"); exit(1)
            }
            try? png.write(to: folder.appendingPathComponent(name))
        }
    }
}
