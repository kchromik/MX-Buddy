import AppKit
import Carbon.HIToolbox
import IOKit.hidsystem

struct Keycap: Equatable {
    let symbol: String
    var legend: String?
}

private struct ModifierKey {
    let cap: Keycap
    let flag: NSEvent.ModifierFlags
    let sideBits: UInt64
    let familyBits: UInt64

    func isPressed(_ flags: NSEvent.ModifierFlags) -> Bool {
        let bits = UInt64(flags.rawValue)
        if bits & familyBits != 0 { return bits & sideBits != 0 }
        return flags.contains(flag)
    }

    static let byCode: [UInt16: Self] = {
        var keys: [UInt16: Self] = [:]
        func pair(_ symbol: String, _ flag: NSEvent.ModifierFlags,
                  _ left: Int, _ right: Int, _ leftMask: Int32, _ rightMask: Int32) {
            for (code, mask, side) in [(left, leftMask, "links"), (right, rightMask, "rechts")] {
                keys[UInt16(code)] = Self(cap: Keycap(symbol: symbol, legend: side), flag: flag,
                                         sideBits: UInt64(mask), familyBits: UInt64(leftMask | rightMask))
            }
        }
        pair("⌘", .command, kVK_Command, kVK_RightCommand, NX_DEVICELCMDKEYMASK, NX_DEVICERCMDKEYMASK)
        pair("⌥", .option, kVK_Option, kVK_RightOption, NX_DEVICELALTKEYMASK, NX_DEVICERALTKEYMASK)
        pair("⌃", .control, kVK_Control, kVK_RightControl, NX_DEVICELCTLKEYMASK, NX_DEVICERCTLKEYMASK)
        pair("⇧", .shift, kVK_Shift, kVK_RightShift, NX_DEVICELSHIFTKEYMASK, NX_DEVICERSHIFTKEYMASK)
        keys[UInt16(kVK_Function)] = Self(cap: Keycap(symbol: "fn"), flag: .function, sideBits: 0, familyBits: 0)
        keys[UInt16(kVK_CapsLock)] = Self(cap: Keycap(symbol: "⇪"), flag: .capsLock, sideBits: 0, familyBits: 0)
        return keys
    }()
}

struct ShortcutCapture {
    private(set) var captured: Chord?
    private(set) var caps: [Keycap] = []
    private var held: [UInt16] = []
    private var pending: Chord?
    private var overlapped = false

    mutating func handle(_ event: NSEvent) {
        guard captured == nil else { return }
        switch event.type {
        case .flagsChanged:
            changedModifier(event.keyCode, event.modifierFlags)
        case .keyDown:
            guard !event.isARepeat, pending == nil else { return }
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            caps = symbols.compactMap { flags.contains($0.0) ? Keycap(symbol: $0.1) : nil }
            var chordFlags = flags
            if held.contains(UInt16(kVK_Function)) {
                caps.append(Keycap(symbol: "fn"))
                chordFlags.insert(.function)
            }
            caps.append(Keycap(symbol: Self.name(of: event)))
            pending = Chord(code: event.keyCode, flags: UInt64(chordFlags.rawValue), label: caps.map(\.symbol).joined())
        case .keyUp:
            if let pending, pending.code == event.keyCode { captured = pending }
        default: break
        }
    }

    private mutating func changedModifier(_ code: UInt16, _ flags: NSEvent.ModifierFlags) {
        guard let modifier = ModifierKey.byCode[code] else { return }
        // Caps Lock sends a change of latch state rather than a matching release.
        if code == kVK_CapsLock, pending == nil, held.isEmpty {
            completeModifier(code, modifier)
            return
        }
        if modifier.isPressed(flags) {
            if !held.contains(code) { held.append(code) }
            if held.count > 1 { overlapped = true }
        } else {
            guard held.contains(code) else { return }
            held.removeAll { $0 == code }
            if pending == nil && held.isEmpty && !overlapped {
                completeModifier(code, modifier)
                return
            }
            if held.isEmpty { overlapped = false }
        }
        if pending == nil { caps = held.compactMap { ModifierKey.byCode[$0]?.cap } }
    }

    private mutating func completeModifier(_ code: UInt16, _ modifier: ModifierKey) {
        caps = [modifier.cap]
        let label = [modifier.cap.symbol, modifier.cap.legend].compactMap { $0 }.joined(separator: " ")
        captured = Chord(code: code, flags: 0, label: label)
    }

    private static func name(of event: NSEvent) -> String {
        let special: [UInt16: String] = [36:"↩", 48:"⇥", 49:"Leertaste", 51:"⌫", 53:"⎋", 76:"⌤",
                                         117:"⌦", 123:"←", 124:"→", 125:"↓", 126:"↑"]
        if let name = special[event.keyCode] { return name }
        let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
        if let scalar = key.unicodeScalars.first, (0xF704...0xF726).contains(scalar.value) {
            return "F" + String(scalar.value - 0xF703)
        }
        return key.isEmpty ? "Taste " + String(event.keyCode) : key
    }
}

extension Chord {
    /// Modifier taps are flagsChanged transitions, including the device-side bit.
    /// Restore the physical keyboard's flags on release (e.g. left ⌘ already held).
    func keyboardEvents(source: CGEventSource?, physicalFlags: CGEventFlags) -> [CGEvent] {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return [] }
        if let modifier = ModifierKey.byCode[code] {
            let mask = CGEventFlags(rawValue: UInt64(modifier.flag.rawValue) | modifier.sideBits)
            down.type = .flagsChanged
            if code == kVK_CapsLock {
                down.flags = physicalFlags.symmetricDifference(mask)
                return [down]
            }
            down.flags = physicalFlags.union(mask)
            up.type = .flagsChanged
            up.flags = physicalFlags
        } else {
            down.flags = CGEventFlags(rawValue: flags)
            up.flags = down.flags
        }
        return [down, up]
    }
}
