import Carbon

/// Global ⌃⌥D push-to-talk hotkey.
final class HotKey {
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var isDown = false

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ctx in
            let me = Unmanaged<HotKey>.fromOpaque(ctx!).takeUnretainedValue()
            me.handle(GetEventKind(event) == UInt32(kEventHotKeyPressed))
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: OSType(0x444F5254), id: 1), // 'DORT'
                            GetApplicationEventTarget(), 0, &ref)
    }

    private func handle(_ pressed: Bool) {
        guard pressed != isDown else { return } // drop key-repeat presses
        isDown = pressed
        pressed ? onPress() : onRelease()
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
