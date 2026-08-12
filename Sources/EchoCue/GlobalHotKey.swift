import Carbon.HIToolbox
import Foundation

enum GlobalAdvanceKey: String, CaseIterable, Identifiable {
    case tab
    case rightArrow
    case space

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tab: return "Tab"
        case .rightArrow: return "Right Arrow"
        case .space: return "Space"
        }
    }

    var symbol: String {
        switch self {
        case .tab: return "⇥"
        case .rightArrow: return "→"
        case .space: return "Space"
        }
    }

    fileprivate var carbonKeyCode: UInt32 {
        switch self {
        case .tab: return UInt32(kVK_Tab)
        case .rightArrow: return UInt32(kVK_RightArrow)
        case .space: return UInt32(kVK_Space)
        }
    }
}

final class GlobalHotKeyController {
    private static let signature: OSType = 0x45435545 // "ECUE"
    private static let identifier: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
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
                guard status == noErr,
                      hotKeyID.signature == GlobalHotKeyController.signature,
                      hotKeyID.id == GlobalHotKeyController.identifier else {
                    return OSStatus(eventNotHandledErr)
                }

                let controller = Unmanaged<GlobalHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                controller.action()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    deinit {
        unregister()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    @discardableResult
    func register(_ key: GlobalAdvanceKey) -> OSStatus {
        unregister()
        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        return RegisterEventHotKey(
            key.carbonKeyCode,
            0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}
