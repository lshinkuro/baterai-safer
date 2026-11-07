import Carbon

/// Global shortcuts via Carbon hot keys, which (unlike event taps) need no Accessibility permission.
enum HotKeys {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var refs: [EventHotKeyRef] = []
    private static var installed = false

    static let ctrlOpt = UInt32(controlKey | optionKey)
    /// (key code, label, tab or nil = toggle the island)
    static let bindings: [(UInt32, String, NTab?)] = [
        (UInt32(kVK_Space), "⌃⌥Space", nil),
        (UInt32(kVK_ANSI_V), "⌃⌥V", .clipboard),
        (UInt32(kVK_ANSI_A), "⌃⌥A", .ai),
        (UInt32(kVK_ANSI_F), "⌃⌥F", .focus),
        (UInt32(kVK_ANSI_G), "⌃⌥G", .git),
    ]

    static func register() {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                HotKeys.actions[hk.id]?()
                return noErr
            }, 1, &spec, nil, nil)
        }
        unregister()
        for (i, b) in bindings.enumerated() {
            let id = UInt32(i + 1)
            actions[id] = { Notch.shared.toggle(b.2) }
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(b.0, ctrlOpt, EventHotKeyID(signature: OSType(0x4253_4146), id: id), GetApplicationEventTarget(), 0, &ref) == noErr,
               let ref { refs.append(ref) }
        }
    }

    static func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
    }
}
