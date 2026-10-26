import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import os
import DynaNotchCore

/// Active CGEventTap on NX_SYSDEFINED (type 14) events so volume / brightness keys can be consumed and the
/// system HUD replaced. Requires Accessibility; until granted it polls every 2 s and attaches when trusted.
/// The tap runs on the main run loop, so `handler` is always called on main.
final class MediaKeyTap: ObservableObject {
    static let shared = MediaKeyTap()

    /// Return true to consume the event (the system will not see it).
    var handler: ((MediaKeyEvent, NSEvent.ModifierFlags) -> Bool)?

    @Published private(set) var isActive: Bool = false

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "mediakeys")
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trustPoll: AnyCancellable?
    private var wantsRunning = false

    private init() {}

    func start() {
        wantsRunning = true
        guard tap == nil else { return }
        if AXIsProcessTrusted(), createTap() { return }
        guard trustPoll == nil else { return }
        trustPoll = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.wantsRunning, self.tap == nil else { return }
                if AXIsProcessTrusted(), self.createTap() {
                    self.trustPoll?.cancel()
                    self.trustPoll = nil
                }
            }
    }

    func stop() {
        wantsRunning = false
        trustPoll?.cancel()
        trustPoll = nil
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        if let t = tap {
            CFMachPortInvalidate(t)
        }
        runLoopSource = nil
        tap = nil
        if isActive { isActive = false }
    }

    // MARK: Private

    private func createTap() -> Bool {
        let mask = CGEventMask(1 << 14)   // NX_SYSDEFINED
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("CGEvent.tapCreate failed (Accessibility not granted?)")
            return false
        }
        let source: CFRunLoopSource? = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        guard let src = source else {
            CFMachPortInvalidate(newTap)
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        runLoopSource = src
        isActive = true
        logger.info("media key tap active")
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap {
                CGEvent.tapEnable(tap: t, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14 else { return Unmanaged.passUnretained(event) }
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let keyEvent = MediaKeyEvent(data1: nsEvent.data1)
        if let handler = handler, handler(keyEvent, nsEvent.modifierFlags) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
