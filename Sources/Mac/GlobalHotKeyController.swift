import Carbon.HIToolbox
import Foundation

final class GlobalHotKeyController {
    private let action: @MainActor @Sendable () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let signature = OSType(0x5348_4252) // SHBR
    private let hotKeyID = UInt32(1)

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register() {
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

        let carbonHotKeyID = EventHotKeyID(signature: self.signature, id: self.hotKeyID)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_K),
            UInt32(cmdKey | shiftKey),
            carbonHotKeyID,
            GetApplicationEventTarget(),
            0,
            &self.hotKeyRef)
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
        guard status == noErr,
              carbonHotKeyID.signature == self.signature,
              carbonHotKeyID.id == self.hotKeyID
        else {
            return
        }
        let action = self.action
        Task { @MainActor in
            action()
        }
    }
}
