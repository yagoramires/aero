import AppKit
import ApplicationServices

// API privada, mas estável há anos (usada por Rectangle, yabai, AltTab): dá o CGWindowID de um
// AXUIElement, que é o único identificador que sobrevive entre consultas.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

// Também privadas e estáveis (yabai, AltTab): em que Spaces a janela está. Minimizada continua
// no Space de onde saiu.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> Unmanaged<CFArray>?

/// Janela de outro app, manipulada pela API de Acessibilidade.
/// Coordenadas sempre globais de cima pra baixo (ver `Display`).
struct Window {
    let element: AXUIElement
    let pid: pid_t
    let id: CGWindowID

    init?(_ element: AXUIElement) {
        var pid: pid_t = 0
        var id: CGWindowID = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.5)
        self.element = element
        self.pid = pid
        self.id = id
    }

    static func focused() -> Window? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let element: AXUIElement = axApp.attribute(kAXFocusedWindowAttribute) else { return nil }
        return Window(element)
    }

    static func at(_ point: CGPoint) -> Window? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        if hit.role == kAXWindowRole { return Window(hit) }
        guard let window: AXUIElement = hit.attribute(kAXWindowAttribute) else { return nil }
        return Window(window)
    }

    /// Janelas normais visíveis no Space atual, da frente pra trás.
    static func allVisible() -> [Window] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var order: [CGWindowID: Int] = [:]
        var pids = Set<pid_t>()
        for (index, entry) in info.enumerated() {
            guard entry[kCGWindowLayer as String] as? Int == 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t else { continue }
            order[id] = index
            pids.insert(pid)
        }
        pids.remove(getpid())

        var windows: [Window] = []
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.3)
            guard let elements: [AXUIElement] = app.attribute(kAXWindowsAttribute) else { continue }
            for element in elements {
                guard let window = Window(element), order[window.id] != nil,
                      window.isStandard, !window.isMinimized else { continue }
                windows.append(window)
            }
        }
        return windows.sorted { order[$0.id]! < order[$1.id]! }
    }

    /// IDs das janelas normais na tela agora (Space atual, não minimizadas), da frente pra trás.
    static func onScreen() -> [CGWindowID] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { entry in
            entry[kCGWindowLayer as String] as? Int == 0 ? entry[kCGWindowNumber as String] as? CGWindowID : nil
        }
    }

    /// Frame real na tela. Vem do WindowServer, porque muitos apps (Electron, WebKit) demoram a
    /// atualizar a posição na Acessibilidade durante arrastes e depois de redimensionados; a
    /// Acessibilidade só entra quando a janela não está visível (minimizada, outro Space).
    /// Frames de todas as janelas visíveis numa consulta só ao WindowServer.
    static func visibleFrames() -> [CGWindowID: CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return info.reduce(into: [:]) { result, entry in
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = entry[kCGWindowBounds as String] as! CFDictionary?,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return }
            result[id] = rect
        }
    }

    var frame: CGRect {
        serverFrame ?? CGRect(origin: element.point(kAXPositionAttribute) ?? .zero,
                              size: element.size(kAXSizeAttribute) ?? .zero)
    }

    private var serverFrame: CGRect? {
        guard let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let bounds = info.first?[kCGWindowBounds as String] as! CFDictionary? else { return nil }
        return CGRect(dictionaryRepresentation: bounds)
    }

    func setFrame(_ rect: CGRect) {
        // Com AXEnhancedUserInterface ligado (VoiceOver, alguns apps Electron) a janela anima
        // e ignora parte das mudanças; desliga só durante a operação.
        let app = AXUIElementCreateApplication(pid)
        let enhanced: Bool = app.attribute("AXEnhancedUserInterface") ?? false
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanFalse) }
        // Tamanho → posição → tamanho: o primeiro tamanho pode ser recusado se a janela ainda
        // não couber na posição nova (ex.: ao trocar de monitor).
        setSize(rect.size)
        setPosition(rect.origin)
        setSize(rect.size)
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanTrue) }
    }

    func setPosition(_ point: CGPoint) {
        var point = point
        if let value = AXValueCreate(.cgPoint, &point) { element.set(kAXPositionAttribute, value) }
    }

    func setSize(_ size: CGSize) {
        var size = size
        if let value = AXValueCreate(.cgSize, &size) { element.set(kAXSizeAttribute, value) }
    }

    func focus() {
        AXUIElementCreateApplication(pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
        element.set(kAXMainAttribute, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    func minimize() {
        element.set(kAXMinimizedAttribute, kCFBooleanTrue)
    }

    var spaces: Set<UInt64> {
        let list = CGSCopySpacesForWindows(CGSMainConnectionID(), 7, [NSNumber(value: id)] as CFArray)?
            .takeRetainedValue() as? [NSNumber] ?? []
        return Set(list.map(\.uint64Value))
    }

    var title: String { element.attribute(kAXTitleAttribute) ?? "" }
    var isMinimized: Bool { element.attribute(kAXMinimizedAttribute) ?? false }
    var isStandard: Bool { element.attribute(kAXSubroleAttribute) == (kAXStandardWindowSubrole as String) }
    var isAlive: Bool { element.role != nil }
    var app: NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }
}

extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    @discardableResult
    func set(_ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, name as CFString, value) == .success
    }

    var role: String? { attribute(kAXRoleAttribute) }

    func point(_ name: String) -> CGPoint? {
        guard let value: AXValue = attribute(name) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    func size(_ name: String) -> CGSize? {
        guard let value: AXValue = attribute(name) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }
}
