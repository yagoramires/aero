// Gera Resources/AppIcon.icns no estilo Liquid Glass do macOS/iOS 26: o mesmo desenho do ícone da
// barra de menu (metade cheia, quadrante cheio, quadrante livre) em peças de vidro sobre azul.
// Uso: swift scripts/make-icon.swift [preview.png]
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func shadow(_ blur: CGFloat, _ y: CGFloat, _ alpha: CGFloat) {
    let s = NSShadow()
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: y)
    s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    s.set()
}

/// Gradiente só na faixa da borda de dentro do `path`: é o brilho especular do vidro.
func rim(_ path: NSBezierPath, width: CGFloat, colors: [NSColor], locations: [CGFloat], angle: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let ring = NSBezierPath()
    ring.append(path)
    ring.lineWidth = width * 2
    // Contorno grosso recortado pelo próprio shape = só a metade de dentro do traço.
    let stroked = NSBezierPath(cgPath: ring.cgPath.copy(strokingWithWidth: width * 2, lineCap: .round,
                                                       lineJoin: .round, miterLimit: 10))
    stroked.addClip()
    NSGradient(colors: colors, atLocations: locations, colorSpace: .sRGB)!.draw(in: path.bounds, angle: angle)
    NSGraphicsContext.restoreGraphicsState()
}

/// Peça de vidro fosco: translúcida, com sombra macia, brilho em cima e reflexo embaixo.
func glass(_ rect: NSRect, radius: CGFloat, filled: Bool) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    shadow(44, -18, filled ? 0.28 : 0.12)
    color(0x0B1F6B, filled ? 0.35 : 0.1).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let top = filled ? 0.96 : 0.16, bottom = filled ? 0.78 : 0.06
    NSGradient(starting: NSColor.white.withAlphaComponent(top), ending: NSColor.white.withAlphaComponent(bottom))!
        .draw(in: rect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    rim(path, width: filled ? 7 : 13,
        colors: [.white, NSColor.white.withAlphaComponent(filled ? 0.15 : 0.35), NSColor.white.withAlphaComponent(filled ? 0.6 : 0.8)],
        locations: [0, 0.55, 1], angle: -75)
}

/// Desenha no canvas de 1024×1024 do grid de ícones do macOS (origem embaixo).
func drawIcon() {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

    NSGraphicsContext.saveGraphicsState()
    shadow(30, -14, 0.3)
    color(0x1747C8).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [color(0x4BA3FF), color(0x2563EB), color(0x1E3A9E)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: body, angle: -90)
    // Luz difusa vinda de cima à esquerda.
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [NSColor.white.withAlphaComponent(0.3).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 1])!
    NSGraphicsContext.current!.cgContext.drawRadialGradient(glow, startCenter: CGPoint(x: 320, y: 900), startRadius: 0,
                                                            endCenter: CGPoint(x: 320, y: 900), endRadius: 640, options: [])
    NSGraphicsContext.restoreGraphicsState()
    rim(squircle, width: 5, colors: [NSColor.white.withAlphaComponent(0.55), NSColor.white.withAlphaComponent(0.05),
                                     NSColor.white.withAlphaComponent(0.2)],
        locations: [0, 0.5, 1], angle: -90)

    // Mesmas proporções do ícone da barra de menu.
    let minX: CGFloat = 228, maxX: CGFloat = 796, minY: CGFloat = 256, maxY: CGFloat = 768
    let gap: CGFloat = 52, radius: CGFloat = 70
    let column = (maxX - minX - gap) / 2, cell = (maxY - minY - gap) / 2
    let right = minX + column + gap
    glass(NSRect(x: right, y: minY, width: column, height: cell), radius: radius, filled: false)
    glass(NSRect(x: minX, y: minY, width: column, height: maxY - minY), radius: radius, filled: true)
    glass(NSRect(x: right, y: minY + cell + gap, width: column, height: cell), radius: radius, filled: true)
}

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
if CommandLine.arguments.count > 1 {
    try! render(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print(iconutil.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "✗ iconutil falhou")
