// HID++ 2.0 over the direct Bluetooth long-report collection.
// All requests and input callbacks are serialized on the main run loop.
import Foundation

enum LinkError: Error { case unavailable, timeout, rejected }

@MainActor
final class LogitechSession {
    private let transport: ReportTransport
    let model: MouseModel
    private var pending: (index: UInt8, function: UInt8, reply: CheckedContinuation<[UInt8], Error>)?
    private var timeout: Task<Void, Never>?
    private var job: Task<Void, Never>?
    private var running = false
    private var revision = 0
    private var profiles = Profiles()
    private var controlsIndex: UInt8 = 0, wheelIndex: UInt8 = 0
    private var controls: [UInt16: Bool] = [:] // divertible CID -> supports raw XY
    private var originals: [UInt16: UInt8] = [:]
    // Diverted Logitech notifications are broadcast. Listen to existing streams
    // without taking ownership of settings that another client must keep on exit.
    private var sharedButtons: Set<UInt16> = []
    private var addedRawXY: Set<UInt16> = []
    private var sharedWheelInverted: Bool?
    private var wheelOriginal: [UInt8]?
    private var positiveLeft = true
    private var pressed: Set<UInt16> = []
    private var stroke = GestureStroke()
    private var wheel = WheelBurst()
    var onInput: ((Input) -> Void)?
    var onStatus: ((String?) -> Void)?

    init(transport: ReportTransport, model: MouseModel) {
        self.transport = transport
        self.model = model
        transport.received = { [weak self] bytes in self?.receive(bytes) }
    }

    func configure(_ value: Profiles) {
        profiles = value
        running = true
        revision += 1
        guard job == nil else { return }
        job = Task { [weak self] in
            guard let self else { return }
            defer { job = nil }
            do {
                if controlsIndex == 0 {
                    controlsIndex = try await request(0, 0, [0x1B, 0x04])[0]
                    guard controlsIndex != 0 else { throw LinkError.unavailable }
                    let count = try await request(controlsIndex, 0)[0]
                    for n in 0..<count {
                        let info = try await request(controlsIndex, 1, [n])
                        if info[4] & 0x20 != 0 { controls[word(info, 0)] = info[8] & 1 != 0 }
                    }
                    wheelIndex = try await request(0, 0, [0x21, 0x50])[0]
                    if wheelIndex != 0 {
                        positiveLeft = try await request(wheelIndex, 0)[4] & 1 == 0
                    }
                }
                while running {
                    let version = revision
                    try await apply()
                    if version == revision { break }
                }
                if running { onStatus?(nil) }
            } catch {
                if running {
                    releaseControls()
                    controlsIndex = 0
                    controls = [:]
                    onStatus?("HID++ antwortet nicht. Verbindung und Logi Options+ prüfen.")
                }
            }
        }
    }

    private func apply() async throws {
        for cid in controls.keys.sorted() {
            guard let input = Input.special[cid] else { continue }
            let isGesture = input == .gesture
            let raw = isGesture && Input.directions.contains { profiles[model, $0] != .native }
            let wanted = profiles[model, input] != .native || raw
            let prefix = [UInt8(cid >> 8), UInt8(truncatingIfNeeded: cid)]
            if wanted {
                if originals[cid] == nil {
                    let status = try await request(controlsIndex, 2, prefix)
                    if status[2] & 0x05 != 0 {
                        sharedButtons.insert(cid)
                        if raw && controls[cid] == true && status[2] & 0x10 == 0 {
                            addedRawXY.insert(cid)
                            _ = try await request(controlsIndex, 3, prefix + [0x30, 0, 0])
                        } else if !raw && addedRawXY.contains(cid) {
                            _ = try await request(controlsIndex, 3, prefix + [0x20, 0, 0])
                            addedRawXY.remove(cid)
                        }
                        continue
                    }
                    sharedButtons.remove(cid)
                    originals[cid] = status[2]
                }
                let bits: UInt8 = controls[cid] == true ? (raw ? 0x33 : 0x23) : 0x03
                _ = try await request(controlsIndex, 3, prefix + [bits, 0, 0])
            } else {
                sharedButtons.remove(cid)
                if addedRawXY.contains(cid) {
                    _ = try await request(controlsIndex, 3, prefix + [0x20, 0, 0])
                    addedRawXY.remove(cid)
                }
                if let original = originals[cid] {
                    _ = try await request(controlsIndex, 3, prefix + [restoreBits(cid, original), 0, 0])
                    originals[cid] = nil
                }
            }
        }
        guard wheelIndex != 0 else { return }
        let left = profiles[model, .thumbLeft] != .native
        let right = profiles[model, .thumbRight] != .native
        if !(left && right), let original = wheelOriginal {
            _ = try await request(wheelIndex, 2, original)
            wheelOriginal = nil
        }
        sharedWheelInverted = nil
        guard (left || right) && wheelOriginal == nil else { return }
        let status = try await request(wheelIndex, 1)
        if status[0] == 1 {
            sharedWheelInverted = status[1] & 1 != 0
        } else if status[0] == 0 && left && right {
            wheelOriginal = [status[0], status[1] & 1]
            _ = try await request(wheelIndex, 2, [1, 0])
        }
    }

    private func restoreBits(_ cid: UInt16, _ flags: UInt8) -> UInt8 {
        controls[cid] == true ? ((flags & 0x11) | 0x22) : ((flags & 1) | 2)
    }

    private func releaseControls() {
        for cid in addedRawXY {
            _ = send(controlsIndex, 0x3E, [UInt8(cid >> 8), UInt8(truncatingIfNeeded: cid), 0x20, 0, 0])
        }
        addedRawXY.removeAll()
        sharedButtons.removeAll()
        sharedWheelInverted = nil
        for (cid, original) in originals {
            _ = send(controlsIndex, 0x3E, [UInt8(cid >> 8), UInt8(truncatingIfNeeded: cid), restoreBits(cid, original), 0, 0])
        }
        if let original = wheelOriginal { _ = send(wheelIndex, 0x2E, original) }
        wheelOriginal = nil
        originals = [:]
        pressed = []
        wheel = WheelBurst()
    }

    func close() {
        running = false
        job?.cancel()
        finish(.failure(LinkError.unavailable))
        releaseControls()
        transport.close()
    }

    private func send(_ index: UInt8, _ command: UInt8, _ args: [UInt8]) -> Bool {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0...3] = [0x11, 0xff, index, command]
        bytes.replaceSubrange(4..<(4 + args.count), with: args)
        return transport.write(bytes)
    }

    private var transaction: UInt8 = 0
    private func request(_ index: UInt8, _ function: UInt8, _ args: [UInt8] = []) async throws -> [UInt8] {
        guard running, !Task.isCancelled else { throw LinkError.unavailable }
        transaction = transaction == 13 ? 8 : max(8, transaction + 1)
        let command = function << 4 | transaction
        return try await withCheckedThrowingContinuation { reply in
            pending = (index, command, reply)
            timeout = Task {
                try? await Task.sleep(for: .milliseconds(900))
                if !Task.isCancelled { finish(.failure(LinkError.timeout)) }
            }
            if !send(index, command, args) { finish(.failure(LinkError.unavailable)) }
        }
    }
    private func finish(_ result: Result<[UInt8], Error>) {
        timeout?.cancel()
        timeout = nil
        let reply = pending?.reply
        pending = nil
        reply?.resume(with: result)
    }

    private func word(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private func receive(_ report: [UInt8]) {
        guard running else { return }
        let bytes = report.count == 19 ? [0x11] + report : report
        guard bytes.count == 20, bytes[0] == 0x11, [0, 0xff].contains(bytes[1]) else { return }
        let index = bytes[2], function = bytes[3], data = Array(bytes.dropFirst(4))
        if let pending {
            if index == pending.index, function == pending.function {
                finish(.success(data))
                return
            }
            if index == 0xFF, function == pending.index, data[0] == pending.function {
                finish(.failure(LinkError.rejected))
                return
            }
        }
        if wheelIndex != 0, index == wheelIndex, function == 0, wheelOriginal != nil || sharedWheelInverted != nil {
            let delta = Int16(bitPattern: word(data, 0))
            guard delta != 0 else { return }
            let reportsPositiveLeft = positiveLeft != (sharedWheelInverted ?? false)
            let input: Input = (delta > 0) == reportsPositiveLeft ? .thumbLeft : .thumbRight
            if wheel.begins(input, at: ProcessInfo.processInfo.systemUptime) { onInput?(input) }
        }
        guard controlsIndex != 0, index == controlsIndex else { return }
        if function == 0 {
            let next = Set(stride(from: 0, to: 8, by: 2).map { word(data, $0) }.filter { originals[$0] != nil || sharedButtons.contains($0) })
            for cid in next.subtracting(pressed) {
                if cid == 0xC3 { stroke = GestureStroke() }
                else if let input = Input.special[cid] { onInput?(input) }
            }
            if pressed.contains(0xC3), !next.contains(0xC3) { onInput?(stroke.input) }
            pressed = next
        } else if function == 0x10, pressed.contains(0xC3), Input.directions.contains(where: { profiles[model, $0] != .native }) {
            stroke.move(dx: Int(Int16(bitPattern: word(data, 0))), dy: Int(Int16(bitPattern: word(data, 2))))
        }
    }
}
