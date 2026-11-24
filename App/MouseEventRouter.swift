import Foundation
import CoreGraphics

struct MouseEventRouter {
    private var consumed: [UInt64: Set<Int64>] = [:]
    private var bursts: [UInt64: [Bool: WheelBurst]] = [:]

    mutating func filter(type: CGEventType, event: CGEvent, sender: UInt64, sources: [UInt64: MouseModel],
                         profiles: Profiles, perform: (Input, MouseModel) -> Void) -> Bool {
        guard let model = sources[sender] else { return false }
        if type == .scrollWheel {
            let h = delta(event, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventDeltaAxis2)
            let v = delta(event, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventDeltaAxis1)
            var handled = false
            var passThrough = false
            for (horizontal, value) in [(true, h), (false, v)] where value != 0 {
                let input: Input = horizontal ? (value > 0 ? .thumbLeft : .thumbRight)
                                              : (value > 0 ? .wheelUp : .wheelDown)
                let begins = bursts[sender, default: [:]][horizontal, default: WheelBurst()]
                    .begins(input, at: ProcessInfo.processInfo.systemUptime)
                guard profiles[model, input] != .native else {
                    passThrough = true
                    continue
                }
                if begins { perform(input, model) }
                handled = true
                let fields: [CGEventField] = horizontal
                    ? [.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2]
                    : [.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1]
                for field in fields { event.setDoubleValueField(field, value: 0) }
            }
            return handled && !passThrough
        }
        let number = event.getIntegerValueField(.mouseEventButtonNumber)
        let buttons: [Input] = [.left, .right, .middle, .back, .forward]
        guard number >= 0, number < buttons.count else { return false }
        let input = buttons[Int(number)]
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard profiles[model, input] != .native else { return false }
            consumed[sender, default: []].insert(number)
            perform(input, model)
            return true
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return consumed[sender]?.remove(number) != nil
        default:
            return consumed[sender]?.contains(number) == true
        }
    }

    private func delta(_ event: CGEvent, _ precise: CGEventField, _ lines: CGEventField) -> Double {
        let value = event.getDoubleValueField(precise)
        return value == 0 ? Double(event.getIntegerValueField(lines)) : value
    }
}
