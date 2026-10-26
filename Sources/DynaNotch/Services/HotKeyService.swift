import AppKit
import Carbon.HIToolbox
import os

/// Global hotkeys via Carbon `RegisterEventHotKey` (no Accessibility permission): ⌃⌥N toggles the panel,
/// ⌃⌥V opens the clipboard tab.
final class HotKeyService {
    static let shared = HotKeyService()

    var onTogglePanel: (() -> Void)?
    var onClipboard: (() -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "hotkey")
    private static let signature: OSType = 0x444E4348   // "DNCH"

    private init() {}

    func start() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            DispatchQueue.main.async { HotKeyService.shared.fire(hotKeyID.id) }
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &handlerRef)
        guard status == noErr else {
            logger.error("InstallEventHandler failed: \(status)")
            return
        }
        let modifiers = UInt32(controlKey | optionKey)
        register(id: 1, keyCode: UInt32(kVK_ANSI_N), modifiers: modifiers)
        register(id: 2, keyCode: UInt32(kVK_ANSI_V), modifiers: modifiers)
    }

    func stop() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        if let handler = handlerRef {
            RemoveEventHandler(handler)
            handlerRef = nil
        }
    }

    private func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotKeyService.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            refs.append(ref)
        } else {
            logger.error("RegisterEventHotKey(\(keyCode)) failed: \(status)")
        }
    }

    private func fire(_ id: UInt32) {
        guard AppSettings.shared.hotkeysEnabled else { return }
        switch id {
        case 1: onTogglePanel?()
        case 2: onClipboard?()
        default: break
        }
    }
}
