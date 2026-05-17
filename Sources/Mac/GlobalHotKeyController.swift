import Carbon.HIToolbox
import Foundation

struct HotKeyCombo {
    let keyCode: UInt32
    let modifiers: UInt32

    static let captureCmdShiftK = HotKeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey))
    static let voiceCmdShiftV = HotKeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
}

final class GlobalHotKeyController {
    private struct Registration {
        let id: UInt32
        let action: @MainActor @Sendable () -> Void
        var hotKeyRef: EventHotKeyRef?
    }

    private let signature = OSType(0x5348_4252) // SHBR
    private var registrations: [UInt32: Registration] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    init() {}

    deinit {
        for registration in self.registrations.values {
            if let ref = registration.hotKeyRef {
                UnregisterEventHotKey(ref)
            }
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func install() {
        guard self.eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
                controller.handleHotKeyEvent(event)
                return noErr
            },
            1,
            &eventType,
            userData,
            &self.eventHandlerRef)
    }

    @discardableResult
    func register(_ combo: HotKeyCombo, action: @escaping @MainActor @Sendable () -> Void) -> UInt32 {
        self.install()
        let id = self.nextID
        self.nextID += 1
        var registration = Registration(id: id, action: action, hotKeyRef: nil)
        let hotKeyID = EventHotKeyID(signature: self.signature, id: id)
        RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registration.hotKeyRef)
        self.registrations[id] = registration
        return id
    }

    private func handleHotKeyEvent(_ event: EventRef) {
        var carbonHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &carbonHotKeyID)
        guard status == noErr, carbonHotKeyID.signature == self.signature else { return }
        guard let registration = self.registrations[carbonHotKeyID.id] else { return }
        let action = registration.action
        Task { @MainActor in
            action()
        }
    }
}
