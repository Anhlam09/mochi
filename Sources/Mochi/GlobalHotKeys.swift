import Carbon.HIToolbox
import Foundation

/// System-wide shortcuts through Carbon's `RegisterEventHotKey`: needs no Accessibility permission and
/// sees no other keystrokes (only the registered combination is delivered).
@MainActor
final class GlobalHotKeys {
    static let shared = GlobalHotKeys()

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var releaseHandlers: [UInt32: @MainActor () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false

    /// Option-M (two keys, easy to hold). It replaces typing "µ" while Mochi's shortcut is on;
    /// Control-M was avoided because Terminal and others treat it as Return.
    static let talkKeyCode = UInt32(kVK_ANSI_M)
    static let talkModifiers = UInt32(optionKey)
    static let talkLabel = "⌥M"

    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32,
                  onRelease: (@MainActor () -> Void)? = nil,
                  handler: @escaping @MainActor () -> Void) -> Bool {
        installHandlerIfNeeded()
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D4F4348), id: id)   // 'MOCH'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        handlers[id] = handler
        releaseHandlers[id] = onRelease
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
        releaseHandlers[id] = nil
    }

    fileprivate func fire(_ id: UInt32, released: Bool) {
        if released { releaseHandlers[id]?() } else { handlers[id]?() }
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        // Both press and release, so a shortcut can work as hold-to-talk.
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotKeys.shared.fire(id, released: released) } }
            return noErr
        }, 2, &specs, nil, nil)
    }
}
