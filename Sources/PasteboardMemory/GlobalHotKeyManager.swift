import Carbon
import Foundation

final class GlobalHotKeyManager {
    private struct Registration {
        var ref: EventHotKeyRef
        var keyCode: UInt32
        var modifiers: UInt32
    }
    private var registrations: [UInt32: Registration] = [:]
    private var handlerRef: EventHandlerRef?
    var onPressed: ((UInt32) -> Void)?

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        installHandlerIfNeeded()
        if registrations[id] != nil { unregister(id: id) }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x50424D45), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            registrations[id] = Registration(ref: ref, keyCode: keyCode, modifiers: modifiers)
        }
    }

    func unregister(id: UInt32) {
        if let reg = registrations.removeValue(forKey: id) {
            UnregisterEventHotKey(reg.ref)
        }
    }

    func unregisterAll() {
        for (_, reg) in registrations { UnregisterEventHotKey(reg.ref) }
        registrations.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        self.handlerRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID(signature: 0, id: 0)
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            let id = hotKeyID.id
            DispatchQueue.main.async { manager.onPressed?(id) }
            return noErr
        }, 1, &eventType, pointer, &handlerRef)
    }

    deinit { unregisterAll() }
}
