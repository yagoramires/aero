import Carbon

/// Atalhos globais via Carbon: não precisam de permissão extra e não deixam a tecla vazar pro app.
final class Hotkeys {
    static let signature = OSType(0x4165_726F) // 'Aero'
    var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    /// Registra o atalho; devolve false se outro app (ex.: Rectangle) já usa a mesma combinação.
    @discardableResult
    func register(_ keyCode: Int, _ modifiers: Int, _ action: @escaping () -> Void) -> Bool {
        installHandler()
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        actions[id] = action
        refs.append(ref)
        return true
    }

    /// No NeyHub o alvo de eventos é de todos: atalho que não é nosso segue para o próximo handler.
    func handle(_ hotKey: EventHotKeyID) -> OSStatus {
        guard hotKey.signature == Self.signature, let action = actions[hotKey.id] else { return OSStatus(eventNotHandledErr) }
        action()
        return noErr
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            guard let userData else { return OSStatus(eventNotHandledErr) }
            return Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue().handle(hotKey)
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}
