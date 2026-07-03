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

    /// Returns true only if the hotkey is now actually registered. If the
    /// combo is already taken by another app (or Carbon otherwise fails), this
    /// rolls back and returns false so callers can reflect the disabled state.
    @discardableResult
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_L),
                  modifiers: UInt32 = UInt32(controlKey | optionKey)) -> Bool {
        guard hotKeyRef == nil else { return true }

        if handlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: OSType(kEventHotKeyPressed))
            let installStatus = InstallEventHandler(GetApplicationEventTarget(),
                                                    hotkeyEventHandler, 1, &eventType,
                                                    nil, &handlerRef)
            guard installStatus == noErr else {
                NSLog("Relaunch: InstallEventHandler failed (\(installStatus))")
                handlerRef = nil
                return false
            }
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x52454c4e), id: 1) // 'RELN'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr, hotKeyRef != nil else {
            NSLog("Relaunch: RegisterEventHotKey failed (\(status)) — ⌃⌥L may be in use")
            hotKeyRef = nil
            return false
        }
        return true
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
