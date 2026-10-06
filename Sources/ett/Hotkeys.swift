import Carbon.HIToolbox
import Foundation

/// Global hotkeys via Carbon's RegisterEventHotKey. One hotkey per slot: the
/// configured modifiers plus the digit 1...9. Works from a plain command-line
/// process as long as the main run loop is running.
enum Hotkeys {
    private static let digitKeyCodes: [Int] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]
    private static var onPress: ((Int) -> Void)?
    private static var refs: [EventHotKeyRef?] = []

    /// Registers all slot hotkeys. `handler` receives the slot number on each press.
    static func register(modifiers: Modifiers, handler: @escaping (Int) -> Void) throws {
        onPress = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var handlerRef: EventHandlerRef?
        let installed = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &handlerRef)
        guard installed == noErr else { throw EttError("could not install hotkey handler (status \(installed))") }

        for (index, keyCode) in digitKeyCodes.prefix(slotCount).enumerated() {
            let slot = index + 1
            let id = EventHotKeyID(signature: 0x4554_5421 /* 'ETT!' */, id: UInt32(slot))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(keyCode), modifiers.carbon, id, GetApplicationEventTarget(), 0, &ref)
            guard status == noErr else {
                let hint = status == eventHotKeyExistsErr ? "another app already uses it" : "status \(status)"
                throw EttError("could not register \(modifiers.symbols)\(slot): \(hint)")
            }
            refs.append(ref)
        }
    }

    private static let callback: EventHandlerUPP = { _, event, _ in
        var id = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard status == noErr else { return status }
        onPress?(Int(id.id))
        return noErr
    }
}
