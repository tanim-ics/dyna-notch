import Foundation
import Combine
import IOKit.pwr_mgt
import os

/// Keeps the display (and Mac) awake via an IOPM assertion while on.
final class KeepAwakeService: ObservableObject {
    static let shared = KeepAwakeService()

    @Published private(set) var isOn = false

    private var assertionID: IOPMAssertionID = 0
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "keepawake")

    private init() {}

    func toggle() {
        set(!isOn)
    }

    func set(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "DynaNotch Keep Awake" as CFString,
                                                     &id)
            guard result == kIOReturnSuccess else {
                logger.error("IOPMAssertionCreateWithName failed: \(result)")
                return
            }
            assertionID = id
            isOn = true
        } else {
            if assertionID != 0 {
                IOPMAssertionRelease(assertionID)
                assertionID = 0
            }
            isOn = false
        }
    }
}
