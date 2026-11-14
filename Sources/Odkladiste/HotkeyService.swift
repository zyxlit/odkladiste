import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys via Carbon `RegisterEventHotKey` without requiring Accessibility permissions.
@MainActor
final class HotkeyService {
    enum Action: UInt32 {
        case newShelf = 1
        case toggleAllShelves = 2
    }

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [Action: EventHotKeyRef] = [:]
    private(set) var registrationStatus: [Action: Bool] = [:]
    private let onAction: @MainActor (Action) -> Void

    init(onAction: @escaping @MainActor (Action) -> Void) {
        self.onAction = onAction
        installHandler()
        registerDefaults()
    }

    func invalidate() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, let action = Action(rawValue: hotKeyID.id) else {
                    return OSStatus(eventNotHandledErr)
                }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    service.onAction(action)
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
    }

    private func registerDefaults() {
        // Ctrl + Option + N -> New shelf near cursor
        register(action: .newShelf, keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey))
        // Ctrl + Option + O -> Toggle all shelves
        register(action: .toggleAllShelves, keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(controlKey | optionKey))
    }

    @discardableResult
    func register(action: Action, keyCode: UInt32, modifiers: UInt32) -> Bool {
        if let existing = hotKeyRefs.removeValue(forKey: action) {
            UnregisterEventHotKey(existing)
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("ODKL"), id: action.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs[action] = ref
            registrationStatus[action] = true
            return true
        }
        registrationStatus[action] = false
        return false
    }

    private func fourCharCode(_ string: String) -> OSType {
        var result: OSType = 0
        for byte in string.utf8.prefix(4) {
            result = (result << 8) | OSType(byte)
        }
        return result
    }
}
