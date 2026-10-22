import Carbon

/// Atalhos globais via Carbon: não precisam de permissão extra e não deixam a tecla vazar pro app.
final class Hotkeys {
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    /// Registra o atalho; devolve false se outro app (ex.: Rectangle) já usa a mesma combinação.
    @discardableResult
    func register(_ keyCode: Int, _ modifiers: Int, _ action: @escaping () -> Void) -> Bool {
        installHandler()
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         EventHotKeyID(signature: OSType(0x4165_726F), id: id), // 'Aero'
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        actions[id] = action
        refs.append(ref)
        return true
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            if let userData {
                Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue().actions[hotKey.id]?()
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}
