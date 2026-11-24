import XCTest

final class MappingTests: XCTestCase {
    func testEverySupportedInputHasOnePlaceOnTheMouseDiagram() {
        for model in MouseModel.allCases {
            let inputs = MousePart.available(on: model).flatMap(\.inputs)
            let expected = Input.allCases.filter { $0 != .panel || model == .four }
            XCTAssertEqual(Set(inputs), Set(expected))
            XCTAssertEqual(inputs.count, expected.count)
            for part in MousePart.available(on: model) {
                let point = part.point(on: model)
                XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y))
            }
        }
    }

    func testMouseTapCanStartWhileHIDPermissionIsPending() {
        let waiting = InputAccess(accessibility: true, monitoring: false, suspended: false)
        XCTAssertTrue(waiting.tapEnabled)
        XCTAssertFalse(waiting.hidEnabled)
        let granted = InputAccess(accessibility: true, monitoring: true, suspended: false)
        XCTAssertTrue(granted.hidEnabled)
        for blocked in [InputAccess(accessibility: false, monitoring: true, suspended: false),
                        InputAccess(accessibility: true, monitoring: true, suspended: true)] {
            XCTAssertFalse(blocked.tapEnabled)
            XCTAssertFalse(blocked.hidEnabled)
        }
    }

    func testProfilesPreserveNativeOverrideAndModelIndependence() throws {
        var profiles = Profiles()
        XCTAssertEqual(profiles[.three, .thumbLeft], .spaceLeft)
        profiles[.three, .thumbLeft] = .native
        profiles[.four, .panel] = .shortcut(.init(code: 40, flags: 1 << 20, label: "⌘K"))
        let decoded = try JSONDecoder().decode(Profiles.self, from: JSONEncoder().encode(profiles))
        XCTAssertEqual(decoded, profiles)
        XCTAssertEqual(decoded[.four, .thumbLeft], .spaceLeft)
        profiles.restoreNative(.four)
        for input in Input.allCases { XCTAssertEqual(profiles[.four, input], .native) }
    }

    func testSystemActionsRespectConfiguredModifierBitsAndDisabledShortcut() {
        let keys: [String: Any] = ["81": ["enabled": true, "value": ["parameters": [65535, 124, 8650752]]],
                                   "79": ["enabled": false]]
        XCTAssertEqual(Action.spaceRight.systemChord(keys)?.flags, 8650752)
        XCTAssertNil(Action.spaceLeft.systemChord(keys))
        XCTAssertEqual(Action.missionControl.systemChord([:])?.code, 126)
    }

    func testWheelFiresOncePerBurstOrDirectionChange() {
        var wheel = WheelBurst()
        XCTAssertTrue(wheel.begins(.thumbRight, at: 0))
        for n in 1...20 { XCTAssertFalse(wheel.begins(.thumbRight, at: Double(n) / 100)) }
        XCTAssertTrue(wheel.begins(.thumbLeft, at: 0.21))
        XCTAssertTrue(wheel.begins(.thumbLeft, at: 0.62))
    }

    func testGestureUsesDominantAxisAndIgnoresJitter() {
        for (x, y, expected): (Int, Int, Input) in [(8, -3, .gesture), (-45, 5, .gestureLeft),
            (52, -12, .gestureRight), (5, -41, .gestureUp), (18, 37, .gestureDown)] {
            var stroke = GestureStroke()
            stroke.move(dx: x, dy: y)
            XCTAssertEqual(stroke.input, expected)
        }
    }
}

@MainActor
private final class TestMouse: ReportTransport {
    var received: (([UInt8]) -> Void)?
    var wheelMode: UInt8 = 0
    var wheelDirection: UInt8 = 0
    var reporting: [UInt16: UInt8] = [:]
    var closed = false
    let cids: [UInt16] = [0xC3, 0xC4, 0x1A0]
    func write(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 20, bytes[0...1] == [0x11, 0xFF] else { return false }
        let index = bytes[2], fn = bytes[3] >> 4
        let cid = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
        var data = [UInt8](repeating: 0, count: 16)
        switch (index, fn) {
        case (0, 0): data[0] = cid == 0x1B04 ? 6 : (cid == 0x2150 ? 9 : 0)
        case (6, 0): data[0] = UInt8(cids.count)
        case (6, 1):
            let key = cids[Int(bytes[4])]
            data[0] = UInt8(key >> 8); data[1] = UInt8(truncatingIfNeeded: key)
            data[4] = 0x20; data[8] = 1
        case (6, 2): data[2] = reporting[cid, default: 0]
        case (6, 3):
            for bit: UInt8 in [1, 0x10] where bytes[6] & (bit << 1) != 0 {
                reporting[cid, default: 0] = (reporting[cid, default: 0] & ~bit) | (bytes[6] & bit)
            }
        case (9, 0): break
        case (9, 1): data[0] = wheelMode; data[1] = wheelDirection
        case (9, 2): wheelMode = bytes[4]
        default: return false
        }
        let response = [0x11, 0, index, bytes[3]] + data
        // IOHID delivers the device reply after the output report returns.
        Task { received?(response) }
        return true
    }
    func close() { closed = true; received = nil }
    func notify(_ index: UInt8, _ function: UInt8, _ data: [UInt8]) {
        received?([0x11, 0, index, function] + data + [UInt8](repeating: 0, count: 16 - data.count))
    }
}

final class DeviceTests: XCTestCase {
    @MainActor
    func testButtonGestureAndWheelNotificationsAndRelease() async {
        let device = TestMouse()
        let session = LogitechSession(transport: device, model: .four)
        var profiles = Profiles()
        for input in [Input.gesture, .gestureLeft, .panel] { profiles[.four, input] = .missionControl }
        var events: [Input] = []
        session.onInput = { events.append($0) }
        await withCheckedContinuation { done in
            session.onStatus = { issue in XCTAssertNil(issue); done.resume() }
            session.configure(profiles)
        }
        XCTAssertEqual(device.reporting[0xC3], 0x11)
        XCTAssertEqual(device.reporting[0x1A0], 1)
        XCTAssertEqual(device.wheelMode, 1)
        device.notify(6, 0, [1, 0xA0]); device.notify(6, 0, [])
        device.notify(6, 0, [0, 0xC3]); device.notify(6, 0, [])
        device.notify(6, 0, [0, 0xC3]); device.notify(6, 0x10, [0xFF, 0xBA, 0, 0])
        device.notify(6, 0, [])
        device.notify(9, 0, [0, 4]); device.notify(9, 0, [0, 2])
        device.notify(9, 0, [0xFF, 0xF0])
        XCTAssertEqual(events, [.panel, .gesture, .gestureLeft, .thumbLeft, .thumbRight])
        session.close()
        XCTAssertTrue(device.closed)
        XCTAssertEqual(device.wheelMode, 0)
        XCTAssertEqual(device.reporting[0x1A0], 0)
        XCTAssertEqual(device.reporting[0xC3], 0)
    }

    @MainActor
    func testExistingDiversionDeliversGesturesAndPreservesOtherClientSettings() async {
        let device = TestMouse()
        device.reporting[0xC3] = 1
        device.wheelMode = 1
        device.wheelDirection = 1
        let session = LogitechSession(transport: device, model: .three)
        var profiles = Profiles()
        profiles[.three, .gesture] = .missionControl
        profiles[.three, .gestureRight] = .spaceRight
        var inputs: [Input] = []
        session.onInput = { inputs.append($0) }
        await withCheckedContinuation { done in
            session.onStatus = { issue in XCTAssertNil(issue); done.resume() }
            session.configure(profiles)
        }
        XCTAssertEqual(device.reporting[0xC3], 0x11)
        device.notify(6, 0, [0, 0xC3]); device.notify(6, 0, [])
        device.notify(6, 0, [0, 0xC3]); device.notify(6, 0x10, [0, 90, 0, 3]); device.notify(6, 0, [])
        device.notify(9, 0, [0, 12])
        XCTAssertEqual(inputs, [.gesture, .gestureRight, .thumbRight])
        session.close()
        XCTAssertEqual(device.reporting[0xC3], 1)
        XCTAssertEqual(device.wheelMode, 1)
    }
}

import CoreGraphics

final class RouterTests: XCTestCase {
    func testDeviceIsolationAndMatchedButtonRelease() throws {
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
        var router = MouseEventRouter()
        var profiles = Profiles()
        profiles[.three, .left] = .missionControl
        var actions = [Input]()
        func filter(_ type: CGEventType, _ sender: UInt64) -> Bool {
            router.filter(type: type, event: event, sender: sender, sources: [7: .three], profiles: profiles) { input, _ in actions.append(input) }
        }
        XCTAssertFalse(filter(.leftMouseDown, 6))
        XCTAssertTrue(filter(.leftMouseDown, 7))
        profiles[.three, .left] = .native
        XCTAssertTrue(filter(.leftMouseDragged, 7))
        XCTAssertFalse(filter(.leftMouseUp, 6))
        XCTAssertTrue(filter(.leftMouseUp, 7))
        XCTAssertFalse(filter(.leftMouseDown, 7))
        XCTAssertEqual(actions, [.left])
    }

    func testWheelLeavesTrackpadAndUnassignedAxisAlone() throws {
        var router = MouseEventRouter()
        let scroll = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                           wheelCount: 2, wheel1: 1, wheel2: 3, wheel3: 0))
        var inputs = [Input]()
        func route(_ id: UInt64) -> Bool {
            router.filter(type: .scrollWheel, event: scroll, sender: id, sources: [7: .three], profiles: Profiles()) {
                input, _ in inputs.append(input)
            }
        }
        XCTAssertFalse(route(2))
        XCTAssertTrue(inputs.isEmpty)
        XCTAssertFalse(route(7))
        XCTAssertEqual(inputs, [.thumbLeft])
        XCTAssertEqual(scroll.getIntegerValueField(.scrollWheelEventDeltaAxis1), 1)
        XCTAssertEqual(scroll.getIntegerValueField(.scrollWheelEventDeltaAxis2), 0)
    }
}
