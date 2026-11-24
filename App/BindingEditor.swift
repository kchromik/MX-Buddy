import SwiftUI

/// The gesture key is a single physical control. Its press and four strokes
/// share one editor so that changing direction doesn't move the action picker.
struct BindingEditor: View {
    let part: MousePart
    let profile: Profiles
    let model: MouseModel
    let assign: (Input, Action) -> Void
    let record: (Input) -> Void
    @State private var stroke: Input = .gesture
    @State private var editing: Input?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if part == .gesture {
                GestureDial(selection: $stroke, configured: {
                    profile[model, $0] != .native
                })
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                actionButton(stroke)
            } else {
                ForEach(part.inputs) { actionButton($0) }
            }
        }
    }

    private func nativeName(for input: Input) -> String {
        if Input.gestureFamily.contains(input), Input.gestureFamily.contains(where: { profile[model, $0] != .native }) {
            return "Unbelegt"
        }
        return Action.native.label
    }

    private func actionButton(_ input: Input) -> some View {
        let action = profile[model, input]
        let name = action == .native ? nativeName(for: input) : action.label
        let presented = Binding(get: { editing == input }, set: { editing = $0 ? input : nil })
        return Button {
            editing = input
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(input.label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Text(name).font(.custom("Outfit", size: 16).weight(.medium)).lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.primary.opacity(scheme == .dark ? 0.055 : 0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.09)) }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(input.label + ", " + name)
        .help("Aktion für „" + input.label + "“ wählen")
        .popover(isPresented: presented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach([Action.native, .spaceLeft, .spaceRight, .missionControl], id: \.self) { choice in
                    ActionChoice(title: choice == .native ? nativeName(for: input) : choice.label,
                                 symbol: choice.symbol, chosen: choice == action) {
                        editing = nil
                        assign(input, choice)
                    }
                }
                Divider().padding(.vertical, 3)
                ActionChoice(title: "Eigenes Tastenkürzel …", symbol: "keyboard", chosen: action.isShortcut) {
                    editing = nil
                    // Dismiss the transient popover before presenting the recorder.
                    DispatchQueue.main.async { record(input) }
                }
            }.padding(6).frame(width: 226)
        }
    }
}

private extension Action {
    var symbol: String {
        switch self {
        case .native: "circle.dashed"
        case .missionControl: "rectangle.3.group"
        case .spaceLeft: "arrow.left.to.line"
        case .spaceRight: "arrow.right.to.line"
        case .shortcut: "keyboard"
        }
    }
    var isShortcut: Bool {
        if case .shortcut = self { return true }
        return false
    }
}

private struct ActionChoice: View {
    let title: String
    let symbol: String
    let chosen: Bool
    let select: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20)
                Text(title)
                Spacer()
                if chosen { Image(systemName: "checkmark").fontWeight(.semibold) }
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .background(.primary.opacity(hovered ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

private struct GestureDial: View {
    @Binding var selection: Input
    let configured: (Input) -> Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Input?

    private let sides: [(Input, String, Double)] = [
        (.gestureUp, "arrow.up", -90), (.gestureRight, "arrow.right", 0),
        (.gestureDown, "arrow.down", 90), (.gestureLeft, "arrow.left", 180)
    ]

    var body: some View {
        ZStack {
            Circle().fill(.primary.opacity(scheme == .dark ? 0.065 : 0.055))
                .overlay { Circle().strokeBorder(.primary.opacity(0.10)) }
                .accessibilityHidden(true)
            ForEach(sides, id: \.0) { input, icon, degrees in
                let wedge = DialSector(angle: degrees)
                Button { selection = input } label: {
                    ZStack {
                        wedge.fill(fill(input))
                        wedge.stroke(.primary.opacity(0.10), lineWidth: 0.6)
                        // The whole wedge responds to clicks, including its label.
                        Image(systemName: icon).font(.system(size: 16, weight: .medium))
                            .foregroundStyle(ink(input))
                            .offset(x: 54 * cos(degrees * .pi / 180), y: 54 * sin(degrees * .pi / 180))
                        if configured(input) {
                            Circle().fill(ink(input)).frame(width: 3, height: 3)
                                .offset(x: 68 * cos(degrees * .pi / 180), y: 68 * sin(degrees * .pi / 180))
                        }
                    }.contentShape(wedge)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(input.label)
                .accessibilityValue(configured(input) ? "Belegt" : "Unbelegt")
                .accessibilityAddTraits(selection == input ? .isSelected : [])
                .help(input.label)
                .onHover { hover(input, $0) }
            }
            Button { selection = .gesture } label: {
                Circle().fill(fill(.gesture))
                    .overlay { Circle().strokeBorder(.primary.opacity(0.13)) }
                    .overlay {
                        Image(systemName: "hand.tap").font(.system(size: 23, weight: .medium))
                            .foregroundStyle(ink(.gesture))
                    }
                    .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).frame(width: 60, height: 60)
            .accessibilityLabel("Gestentaste drücken")
            .accessibilityAddTraits(selection == .gesture ? .isSelected : [])
            .help("Gestentaste drücken")
            .onHover { hover(.gesture, $0) }
        }
        .frame(width: 160, height: 160)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: selection)
    }

    private func hover(_ input: Input, _ inside: Bool) {
        if inside { hovered = input } else if hovered == input { hovered = nil }
    }

    private func fill(_ input: Input) -> LinearGradient {
        let high: Color, low: Color
        if selection == input {
            high = Color(white: scheme == .dark ? 0.99 : 0.27)
            low = Color(white: scheme == .dark ? 0.82 : 0.14)
        } else {
            let raised = hovered == input ? 0.075 : 0.0
            high = Color(white: scheme == .dark ? 0.24 + raised : 0.985 - raised)
            low = Color(white: scheme == .dark ? 0.19 + raised : 0.94 - raised)
        }
        return LinearGradient(colors: [high, low], startPoint: .top, endPoint: .bottom)
    }

    private func ink(_ input: Input) -> Color {
        selection == input ? (scheme == .dark ? .black : .white) : .primary
    }
}

/// Four individually hit-testable segments with a gap around the central press.
private struct DialSector: Shape {
    let angle: Double
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - 3
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: .degrees(angle - 43.5),
                    endAngle: .degrees(angle + 43.5), clockwise: false)
        path.addArc(center: center, radius: outer * 0.425, startAngle: .degrees(angle + 42),
                    endAngle: .degrees(angle - 42), clockwise: true)
        path.closeSubpath()
        return path
    }
}
