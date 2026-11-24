import Foundation

enum MouseModel: String, CaseIterable, Codable, Identifiable {
    case three = "MX Master 3S", four = "MX Master 4"
    var id: Self { self }

    init?(product: String) {
        let name = product.lowercased()
        if name.contains("mx master 3s") { self = .three }
        else if name.contains("mx master 4") { self = .four }
        else { return nil }
    }
}

enum Input: String, CaseIterable, Codable, Identifiable {
    case thumbLeft, thumbRight, gesture, gestureLeft, gestureRight, gestureUp, gestureDown
    case panel, back, forward, middle, mode, wheelUp, wheelDown, left, right
    var id: Self { self }
    static let directions: [Self] = [.gestureLeft, .gestureRight, .gestureUp, .gestureDown]
    static let gestureFamily = [.gesture] + directions

    var label: String {
        switch self {
        case .thumbLeft: "Daumenrad nach links"
        case .thumbRight: "Daumenrad nach rechts"
        case .gesture: "Gestentaste drücken"
        case .gestureLeft: "Nach links bewegen"
        case .gestureRight: "Nach rechts bewegen"
        case .gestureUp: "Nach oben bewegen"
        case .gestureDown: "Nach unten bewegen"
        case .panel: "Daumenfläche drücken"
        case .back: "Zurücktaste"
        case .forward: "Vorwärtstaste"
        case .middle: "Mittelklick"
        case .mode: "Radmodus-Taste"
        case .wheelUp: "Nach oben scrollen"
        case .wheelDown: "Nach unten scrollen"
        case .left: "Linksklick"
        case .right: "Rechtsklick"
        }
    }
    var initial: Action {
        switch self {
        case .thumbLeft: .spaceLeft
        case .thumbRight: .spaceRight
        default: .native
        }
    }
    static let special: [UInt16: Self] = [0xC3: .gesture, 0xC4: .mode, 0x1A0: .panel,
                                           0x52: .middle, 0x53: .back, 0x56: .forward]
}

struct Chord: Codable, Equatable, Hashable {
    var code: UInt16
    var flags: UInt64
    var label: String
}

enum Action: Codable, Equatable, Hashable {
    case native, spaceLeft, spaceRight, missionControl, shortcut(Chord)

    var label: String {
        switch self {
        case .native: "Standardverhalten"
        case .spaceLeft: "Space nach links"
        case .spaceRight: "Space nach rechts"
        case .missionControl: "Mission Control"
        case .shortcut(let chord): chord.label
        }
    }
}

struct Profiles: Codable, Equatable {
    private var entries: [String: [String: Action]] = [:]
    subscript(_ model: MouseModel, _ input: Input) -> Action {
        get { entries[model.rawValue]?[input.rawValue] ?? input.initial }
        set { entries[model.rawValue, default: [:]][input.rawValue] = newValue }
    }
    mutating func restoreNative(_ model: MouseModel) {
        for input in Input.allCases { self[model, input] = .native }
    }
}

struct WheelBurst {
    private var previous: Input?
    private var lastTime: TimeInterval = 0

    mutating func begins(_ input: Input, at time: TimeInterval) -> Bool {
        defer { previous = input; lastTime = time }
        return previous != input || time - lastTime > 0.24
    }
}

struct GestureStroke {
    private var x = 0, y = 0
    mutating func move(dx: Int, dy: Int) { x += dx; y += dy }

    var input: Input {
        guard max(abs(x), abs(y)) >= 35 else { return .gesture }
        if abs(x) >= abs(y) { return x < 0 ? .gestureLeft : .gestureRight }
        return y < 0 ? .gestureUp : .gestureDown
    }
}
