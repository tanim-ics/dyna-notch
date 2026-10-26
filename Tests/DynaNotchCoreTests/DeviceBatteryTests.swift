import XCTest
@testable import DynaNotchCore

final class DeviceBatteryTests: XCTestCase {
    private let profilerJSON = """
    {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
      "device_connected":[
        {"MX Master 3S":{"device_address":"d4:10:0a:dd:29:7b","device_minorType":"Mouse"}},
        {"Tanim’s AirPods Pro 3":{"device_address":"BC:80:4E:D8:8D:21","device_batteryLevelCase":"22\\u00a0%",
          "device_batteryLevelLeft":"86\\u00a0%","device_batteryLevelRight":"84 %","device_minorType":"Headphones"}},
        {"TH108 PRO-1":{"device_address":"FC:AE:73:72:1F:CC","device_minorType":"Keyboard","device_batteryLevelMain":"90%"}}
      ],
      "device_not_connected":[{"Old Pad":{"device_address":"10:18:49:07:1C:9E","device_minorType":"Gamepad"}}]}]}
    """

    func testPercent() {
        XCTAssertEqual(BluetoothProfilerParser.percent("86\u{a0}%"), 86)
        XCTAssertEqual(BluetoothProfilerParser.percent("100 %"), 100)
        XCTAssertEqual(BluetoothProfilerParser.percent("250%"), 100)
        XCTAssertNil(BluetoothProfilerParser.percent("n/a"))
    }

    func testParseConnectedOnly() {
        let devices = BluetoothProfilerParser.parse(Data(profilerJSON.utf8))
        XCTAssertEqual(devices.map(\.name), ["MX Master 3S", "Tanim’s AirPods Pro 3", "TH108 PRO-1"])
        XCTAssertEqual(devices[0].id, "D4:10:0A:DD:29:7B")
        XCTAssertEqual(devices[0].kind, .mouse)
        XCTAssertNil(devices[0].displayLevel)
        XCTAssertEqual(devices[1].kind, .airpods)
        XCTAssertEqual(devices[1].left, 86)
        XCTAssertEqual(devices[1].caseLevel, 22)
        XCTAssertEqual(devices[1].displayLevel, 84)
        XCTAssertEqual(devices[2].kind, .keyboard)
        XCTAssertEqual(devices[2].displayLevel, 90)
        XCTAssertTrue(BluetoothProfilerParser.parse(Data("garbage".utf8)).isEmpty)
    }

    func testDisplayLevelFallbacks() {
        XCTAssertEqual(DeviceBattery(id: "a", name: "a", kind: .airpods, right: 40).displayLevel, 40)
        XCTAssertEqual(DeviceBattery(id: "a", name: "a", kind: .airpods, caseLevel: 10).displayLevel, 10)
        XCTAssertEqual(DeviceBattery(id: "a", name: "a", kind: .mouse, level: 5, left: 1).displayLevel, 5)
    }

    func testMerge() {
        let mac = DeviceBattery(id: "mac", name: "MacBook Pro", kind: .mac, level: 80, detail: "Health 100%")
        let profiler = [DeviceBattery(id: "D4", name: "MX Master 3S", kind: .mouse),
                        DeviceBattery(id: "BC", name: "AirPods", kind: .airpods, left: 80, right: 82)]
        let gatt = [DeviceBattery(id: "uuid-1", name: "mx master 3s", kind: .other, level: 95),
                    DeviceBattery(id: "BC", name: "AirPods", kind: .airpods, level: 50)]
        let merged = DeviceBatteryMerge.merge([profiler, gatt, [mac]])
        XCTAssertEqual(merged.map(\.name), ["MacBook Pro", "AirPods", "MX Master 3S"])
        XCTAssertEqual(merged[2].level, 95)
        XCTAssertEqual(merged[2].kind, .mouse)
        XCTAssertEqual(merged[1].level, 50)
        XCTAssertEqual(merged[1].left, 80)
    }

    func testKindsAndMaterial() {
        XCTAssertEqual(DeviceKind.classify(minorType: nil, name: "Magic Trackpad"), .trackpad)
        XCTAssertEqual(DeviceKind.classify(minorType: "Headset", name: "XM6"), .headphones)
        XCTAssertEqual(DeviceKind.classify(minorType: nil, name: "Thing"), .other)
        for kind in DeviceKind.allCases { XCTAssertFalse(kind.symbolName.isEmpty) }
        XCTAssertEqual(IslandMaterial.glass.title, "Glass")
    }
}
