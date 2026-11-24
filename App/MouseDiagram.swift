import SwiftUI

enum MouseAngle: String, CaseIterable, Identifiable {
    case side = "Seite", top = "Oben"
    var id: Self { self }
}

enum MousePart: String, CaseIterable, Identifiable {
    case thumb = "Daumenrad", gesture = "Gestentaste", panel = "Daumenfläche"
    case back = "Zurücktaste", forward = "Vorwärtstaste"
    case left = "Linke Maustaste", right = "Rechte Maustaste", wheel = "Scrollrad", mode = "Radmodus-Taste"

    var id: Self { self }
    var angle: MouseAngle {
        switch self {
        case .left, .right, .wheel, .mode: .top
        default: .side
        }
    }
    var inputs: [Input] {
        switch self {
        case .thumb: [.thumbLeft, .thumbRight]
        case .gesture: Input.gestureFamily
        case .panel: [.panel]
        case .back: [.back]
        case .forward: [.forward]
        case .left: [.left]
        case .right: [.right]
        case .wheel: [.middle, .wheelUp, .wheelDown]
        case .mode: [.mode]
        }
    }

    // Normalized coordinates in the cropped product photos, measured from the top left.
    func point(on model: MouseModel) -> CGPoint {
        let four = model == .four
        switch self {
        case .thumb: return four ? CGPoint(x: 0.52, y: 0.19) : CGPoint(x: 0.50, y: 0.26)
        case .gesture: return four ? CGPoint(x: 0.395, y: 0.477) : CGPoint(x: 0.615, y: 0.88)
        case .panel: return CGPoint(x: 0.54, y: 0.68)
        case .back: return four ? CGPoint(x: 0.600, y: 0.316) : CGPoint(x: 0.585, y: 0.383)
        case .forward: return four ? CGPoint(x: 0.503, y: 0.410) : CGPoint(x: 0.478, y: 0.467)
        case .left: return CGPoint(x: 0.44, y: 0.19)
        case .right: return CGPoint(x: 0.79, y: 0.20)
        case .wheel: return four ? CGPoint(x: 0.60, y: 0.226) : CGPoint(x: 0.614, y: 0.21)
        case .mode: return four ? CGPoint(x: 0.60, y: 0.425) : CGPoint(x: 0.614, y: 0.391)
        }
    }
    static func available(on model: MouseModel) -> [Self] {
        allCases.filter { model == .four || $0 != .panel }
    }
}

struct MouseDiagram: View {
    let model: MouseModel
    @Binding var part: MousePart
    @State private var hovered: MousePart?
    private var angle: MouseAngle { part.angle }

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geometry in
                let key = "mx-" + (model == .three ? "3s" : "4") + (angle == .side ? "-side" : "-top")
                if let photo = NSImage(named: key) {
                    let factor = min(geometry.size.width / photo.size.width, geometry.size.height / photo.size.height)
                    let size = CGSize(width: photo.size.width * factor, height: photo.size.height * factor)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: photo).resizable().interpolation(.high)
                            .frame(width: size.width, height: size.height).accessibilityHidden(true)
                        ForEach(MousePart.available(on: model).filter { $0.angle == angle }) { item in
                            let point = item.point(on: model)
                            Button { part = item } label: {
                                ZStack {
                                    Circle().fill(.black.opacity(0.65))
                                    Circle().strokeBorder(.white, lineWidth: 2)
                                    Circle().fill(.white).padding(item == part ? 5 : 7)
                                }
                                .frame(width: item == part || hovered == item ? 20 : 16,
                                       height: item == part || hovered == item ? 20 : 16)
                                .shadow(color: .black.opacity(0.40), radius: 2, y: 1)
                                .frame(width: 28, height: 28).contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.rawValue + " auswählen")
                            .accessibilityAddTraits(part == item ? .isSelected : [])
                            .help(item.rawValue)
                            .onHover { inside in
                                if inside { hovered = item } else if hovered == item { hovered = nil }
                            }
                            .position(x: size.width * point.x, y: size.height * point.y)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            Picker("Mausansicht", selection: Binding(get: { angle }, set: { part = $0 == .side ? .thumb : .wheel })) {
                ForEach(MouseAngle.allCases) { view in Text(view.rawValue).tag(view) }
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 148)
        }
    }
}
