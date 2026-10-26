import XCTest
@testable import DynaNotchCore

final class PowerEventDetectorTests: XCTestCase {
    func battery(_ level: Double, plugged: Bool = false) -> BatteryInfo {
        BatteryInfo(level: level, isCharging: plugged && level < 1, isPluggedIn: plugged)
    }

    func testFirstCallRecordsOnly() {
        var d = PowerEventDetector()
        XCTAssertEqual(d.update(battery(0.05)), [])
    }

    func testPlugAndUnplug() {
        var d = PowerEventDetector()
        _ = d.update(battery(0.5))
        let plugged = battery(0.5, plugged: true)
        XCTAssertEqual(d.update(plugged), [.pluggedIn(plugged)])
        XCTAssertEqual(d.update(plugged), [])
        let unplugged = battery(0.5)
        XCTAssertEqual(d.update(unplugged), [.unplugged(unplugged)])
    }

    func testLowBatteryOnceAtThreshold() {
        var d = PowerEventDetector()
        _ = d.update(battery(0.25))
        XCTAssertEqual(d.update(battery(0.21)), [])
        let low = battery(0.20)
        XCTAssertEqual(d.update(low), [.lowBattery(low, threshold: 20)])
        XCTAssertEqual(d.update(battery(0.19)), [])
        XCTAssertEqual(d.update(battery(0.15)), [])
        let critical = battery(0.10)
        XCTAssertEqual(d.update(critical), [.lowBattery(critical, threshold: 10)])
        XCTAssertEqual(d.update(battery(0.05)), [])
    }

    func testMultipleThresholdsCrossedEmitsLowestOnly() {
        var d = PowerEventDetector()
        _ = d.update(battery(0.30))
        let drop = battery(0.08)
        XCTAssertEqual(d.update(drop), [.lowBattery(drop, threshold: 10)])
        XCTAssertEqual(d.update(battery(0.07)), [])
    }

    func testNoLowBatteryWhilePluggedIn() {
        var d = PowerEventDetector()
        _ = d.update(battery(0.25, plugged: true))
        XCTAssertEqual(d.update(battery(0.15, plugged: true)), [])
    }

    func testStartingBelowThresholdDoesNotFireForIt() {
        var d = PowerEventDetector()
        _ = d.update(battery(0.15))
        XCTAssertEqual(d.update(battery(0.14)), [])
        let critical = battery(0.10)
        XCTAssertEqual(d.update(critical), [.lowBattery(critical, threshold: 10)])
    }

    func testRearmAfterHysteresis() {
        var d = PowerEventDetector()
        _ = d.update(battery(0.30))
        _ = d.update(battery(0.19))
        XCTAssertEqual(d.update(battery(0.24)), []) // not > 25 → still disarmed
        XCTAssertEqual(d.update(battery(0.19)), [])
        _ = d.update(battery(0.26))                 // > 25 → re-armed
        let low = battery(0.20)
        XCTAssertEqual(d.update(low), [.lowBattery(low, threshold: 20)])
    }

    func testRearmWhenPluggedIn() {
        var d = PowerEventDetector()
        _ = d.update(battery(0.30))
        _ = d.update(battery(0.20))                    // fires 20
        _ = d.update(battery(0.22, plugged: true))     // plugged above threshold → re-armed
        let unplugged = battery(0.22)
        XCTAssertEqual(d.update(unplugged), [.unplugged(unplugged)])
        let low = battery(0.20)
        XCTAssertEqual(d.update(low), [.lowBattery(low, threshold: 20)])
    }

    func testUnplugBelowThresholdFiresOnlyOnRealCrossing() {
        var d = PowerEventDetector()
        _ = d.update(battery(0.15, plugged: true))
        let unplugged = battery(0.15)
        XCTAssertEqual(d.update(unplugged), [.unplugged(unplugged)])
        let critical = battery(0.09)
        XCTAssertEqual(d.update(critical), [.lowBattery(critical, threshold: 10)])
    }

    func testCustomThresholds() {
        var d = PowerEventDetector(thresholds: [5, 50])
        _ = d.update(battery(0.6))
        let half = battery(0.5)
        XCTAssertEqual(d.update(half), [.lowBattery(half, threshold: 50)])
        let five = battery(0.05)
        XCTAssertEqual(d.update(five), [.lowBattery(five, threshold: 5)])
    }

    func testBatteryInfoDefaults() {
        let info = BatteryInfo(level: 0.4, isCharging: false, isPluggedIn: false)
        XCTAssertNil(info.minutesToEmpty)
        XCTAssertNil(info.minutesToFull)
    }
}

final class BluetoothTests: XCTestCase {
    func testAirPodsFamily() {
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "Tanim's AirPods Max", majorClass: 0x04, minorClass: 0x06), .airpodsMax)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "AirPods Pro", majorClass: 0, minorClass: 0), .airpodsPro)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "airpods", majorClass: 0, minorClass: 0), .airpods)
    }

    func testHeadphoneNames() {
        for name in ["Beats Studio", "My Headphones", "Galaxy Buds2", "WH-1000XM5", "Bose QC45"] {
            XCTAssertEqual(BluetoothDeviceKind.classify(name: name, majorClass: 0x1F, minorClass: 0), .headphones, name)
        }
    }

    func testAudioClass() {
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "X", majorClass: 0x04, minorClass: 0x06), .headphones)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "X", majorClass: 0x04, minorClass: 0x01), .headphones)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "X", majorClass: 0x04, minorClass: 0x02), .headphones)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "JBL Flip", majorClass: 0x04, minorClass: 0x05), .speaker)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "X", majorClass: 0x04, minorClass: 0x0B), .headphones)
    }

    func testPeripheralClass() {
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "Magic Keyboard", majorClass: 0x05, minorClass: 0x10), .keyboard)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "Magic Mouse", majorClass: 0x05, minorClass: 0x20), .mouse)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "Magic Trackpad", majorClass: 0x05, minorClass: 0x20), .trackpad)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "DualSense", majorClass: 0x05, minorClass: 0x02), .gamepad)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "Stick", majorClass: 0x05, minorClass: 0x01), .gamepad)
    }

    func testNameFallbacks() {
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "Logitech Keyboard", majorClass: 0, minorClass: 0), .keyboard)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "MX Mouse", majorClass: 0, minorClass: 0), .mouse)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "Trackpad", majorClass: 0x05, minorClass: 0x30), .trackpad)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "Xbox Wireless Controller", majorClass: 0x05, minorClass: 0x08), .gamepad)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "Unknown Gadget", majorClass: 0x01, minorClass: 0x03), .generic)
        XCTAssertEqual(BluetoothDeviceKind.classify(name: "", majorClass: 0, minorClass: 0), .generic)
    }

    func testSymbolNames() {
        let expected: [BluetoothDeviceKind: String] = [
            .airpods: "airpods", .airpodsPro: "airpodspro", .airpodsMax: "airpodsmax", .headphones: "headphones",
            .speaker: "hifispeaker.fill", .keyboard: "keyboard", .mouse: "computermouse",
            .trackpad: "rectangle.and.hand.point.up.left", .gamepad: "gamecontroller.fill",
            .generic: "dot.radiowaves.left.and.right",
        ]
        XCTAssertEqual(expected.count, BluetoothDeviceKind.allCases.count)
        for kind in BluetoothDeviceKind.allCases {
            XCTAssertEqual(kind.symbolName, expected[kind])
        }
    }

    func testBluetoothEvent() {
        let e = BluetoothEvent(address: "aa-bb", name: "AirPods", kind: .airpods, battery: 80, connected: true)
        XCTAssertEqual(e, BluetoothEvent(address: "aa-bb", name: "AirPods", kind: .airpods, battery: 80, connected: true))
        XCTAssertNotEqual(e, BluetoothEvent(address: "aa-bb", name: "AirPods", kind: .airpods, battery: nil, connected: true))
    }
}

final class FocusParserTests: XCTestCase {
    let assertionsWork = """
    {"data":[{"storeAssertionRecords":[{"assertionUUID":"5C7E4F0A-0000-0000-0000-000000000000",\
    "assertionSource":{"assertionClientIdentifier":"com.apple.controlcenter"},"assertionStartDateTimestamp":716000000.5,\
    "assertionDetails":{"assertionDetailsIdentifier":"com.apple.focus.control-center",\
    "assertionDetailsModeIdentifier":"com.apple.focus.work","assertionDetailsReason":"user-action"}}]}],\
    "header":{"timestamp":716000001.1}}
    """.data(using: .utf8)!

    let assertionsNone = #"{"data":[{"storeAssertionRecords":[]}],"header":{}}"#.data(using: .utf8)!
    let assertionsMissing = #"{"data":[{}]}"#.data(using: .utf8)!

    let configurations = """
    {"data":[{"modeConfigurations":{\
    "com.apple.focus.work":{"mode":{"name":"Deep Work","symbolImageName":"laptopcomputer",\
    "modeIdentifier":"com.apple.focus.work","semanticType":3},"triggers":{"triggers":[]}},\
    "com.apple.donotdisturb.mode.default":{"mode":{"name":"Do Not Disturb","symbolImageName":"moon.fill"}},\
    "com.apple.focus.custom.ABC":{"mode":{"name":"","symbolImageName":null}}}}]}
    """.data(using: .utf8)!

    func assertions(for id: String) -> Data {
        #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"\#(id)"}}]}]}"#
            .data(using: .utf8)!
    }

    func testActiveModeIdentifier() {
        XCTAssertEqual(FocusParser.activeModeIdentifier(assertionsJSON: assertionsWork), "com.apple.focus.work")
        XCTAssertNil(FocusParser.activeModeIdentifier(assertionsJSON: assertionsNone))
        XCTAssertNil(FocusParser.activeModeIdentifier(assertionsJSON: assertionsMissing))
    }

    func testStateUsesConfiguration() {
        let s = FocusParser.state(assertionsJSON: assertionsWork, configurationsJSON: configurations)
        XCTAssertEqual(s, FocusState(modeIdentifier: "com.apple.focus.work", name: "Deep Work", symbol: "laptopcomputer"))
        XCTAssertTrue(s.isActive)
    }

    func testStateFallsBackWithoutConfiguration() {
        let s = FocusParser.state(assertionsJSON: assertionsWork, configurationsJSON: nil)
        XCTAssertEqual(s, FocusState(modeIdentifier: "com.apple.focus.work", name: "Work", symbol: "briefcase.fill"))
    }

    func testEmptyConfigValuesFallBack() {
        let s = FocusParser.state(assertionsJSON: assertions(for: "com.apple.focus.custom.ABC"), configurationsJSON: configurations)
        XCTAssertEqual(s, FocusState(modeIdentifier: "com.apple.focus.custom.ABC", name: "Focus", symbol: "moon.fill"))
    }

    func testKnownFallbacks() {
        let cases: [(String, String, String)] = [
            ("com.apple.donotdisturb.mode.default", "Do Not Disturb", "moon.fill"),
            ("com.apple.sleep.sleep-mode", "Sleep", "bed.double.fill"),
            ("com.apple.donotdisturb.mode.driving", "Driving", "car.fill"),
            ("com.apple.focus.work", "Work", "briefcase.fill"),
            ("com.apple.focus.personal-time", "Personal", "person.fill"),
            ("com.apple.focus.reading", "Reading", "book.fill"),
            ("com.apple.focus.Fitness", "Fitness", "figure.run"),
            ("com.apple.focus.gaming", "Gaming", "gamecontroller.fill"),
            ("com.apple.focus.mindfulness", "Mindfulness", "brain.head.profile"),
            ("com.apple.focus.custom.XYZ", "Focus", "moon.fill"),
        ]
        for (id, name, symbol) in cases {
            let s = FocusParser.state(assertionsJSON: assertions(for: id), configurationsJSON: nil)
            XCTAssertEqual(s, FocusState(modeIdentifier: id, name: name, symbol: symbol), id)
        }
    }

    func testInactive() {
        XCTAssertEqual(FocusState.inactive, FocusState(modeIdentifier: nil, name: "Focus", symbol: "moon.fill"))
        XCTAssertFalse(FocusState.inactive.isActive)
        XCTAssertEqual(FocusParser.state(assertionsJSON: assertionsNone, configurationsJSON: configurations), .inactive)
    }

    func testGarbageNeverCrashes() {
        let samples = ["", "null", "[]", "{}", "{\"data\":7}", "{\"data\":[]}", "{\"data\":[1]}",
                       "{\"data\":[{\"storeAssertionRecords\":[7]}]}",
                       "{\"data\":[{\"storeAssertionRecords\":[{\"assertionDetails\":{\"assertionDetailsModeIdentifier\":5}}]}]}",
                       "\u{FF}\u{FE}garbage"]
        for sample in samples {
            let data = Data(sample.utf8)
            XCTAssertEqual(FocusParser.state(assertionsJSON: data, configurationsJSON: data), .inactive, sample)
        }
        let badConfig = Data("{\"data\":[{\"modeConfigurations\":[]}]}".utf8)
        XCTAssertEqual(FocusParser.state(assertionsJSON: assertionsWork, configurationsJSON: badConfig).name, "Work")
    }
}
