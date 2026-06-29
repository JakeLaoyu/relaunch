import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey via the Carbon Hot Key API (no Accessibility
/// permission required). Default: ⌃⌥L.
final class HotkeyManager {
    let action: () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    static var shared: HotkeyManager?

    init(action: @escaping () -> Void) {
        self.action = action
        HotkeyManager.shared = self
    }

    func register(keyCode: UInt32 = UInt32(kVK_ANSI_L),
                  modifiers: UInt32 = UInt32(controlKey | optionKey)) {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler,
                            1, &eventType, nil, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x52454c4e), id: 1) // 'RELN'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}

/// C callback invoked when the hotkey fires.
private func hotkeyEventHandler(_ next: EventHandlerCallRef?,
                                _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    HotkeyManager.shared?.action()
    return noErr
}
