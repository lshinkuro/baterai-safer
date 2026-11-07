import Carbon

/// Global shortcuts via Carbon hot keys, which (unlike event taps) need no Accessibility permission.
enum HotKeys {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var refs: [EventHotKeyRef] = []
    private static var installed = false

    static let ctrlOpt = UInt32(controlKey | optionKey)
    /// (key code, keys, what it does, action)
    static let bindings: [(UInt32, String, String, () -> Void)] = [
        (UInt32(kVK_Space), "⌃⌥Space", "Buka / tutup notch", { Notch.shared.toggle(nil) }),
        (UInt32(kVK_ANSI_N), "⌃⌥N", "Catatan", { Notch.shared.toggle(.notes) }),
        (UInt32(kVK_ANSI_D), "⌃⌥D", "Dev Utils", { Notch.shared.toggle(.dev) }),
        (UInt32(kVK_ANSI_V), "⌃⌥V", "Clipboard", { Notch.shared.toggle(.clipboard) }),
        (UInt32(kVK_ANSI_A), "⌃⌥A", "AI", { Notch.shared.toggle(.ai) }),
        (UInt32(kVK_ANSI_T), "⌃⌥T", "Salin teks dari layar", { Notch.shared.ocr() }),
        (UInt32(kVK_ANSI_F), "⌃⌥F", "Fokus", { Notch.shared.toggle(.focus) }),
        (UInt32(kVK_ANSI_G), "⌃⌥G", "Git", { Notch.shared.toggle(.git) }),
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
            actions[id] = b.3
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
