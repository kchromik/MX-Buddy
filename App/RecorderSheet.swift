import SwiftUI

struct RecorderSheet: View {
    let input: Input
    let save: (Action) -> Void
    let cancel: () -> Void
    @State private var capture = ShortcutCapture()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var listening: Bool { capture.captured == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(input.label).font(.callout).foregroundStyle(.secondary)
                Text("Tastenkürzel aufnehmen").font(.custom("Outfit", size: 27).weight(.medium))
            }

            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: listening ? "record.circle" : "checkmark.circle.fill")
                        .foregroundStyle(listening ? Color.red : Color.green)
                    Text(listening ? "Aufnahme aktiv" : "Erfasst").fontWeight(.medium)
                }.font(.caption)
                ZStack {
                    if capture.caps.isEmpty {
                        PhysicalKey(symbol: "keyboard", legend: nil, placeholder: true)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            keycaps(scale: 1)
                            keycaps(scale: 0.68)
                            Text(capture.caps.map(\.symbol).joined(separator: " ")).font(.title)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 91)
                Text(listening ? "Eine Taste oder Kombination drücken und loslassen." : "Mit „Übernehmen“ dieser Maustaste zuweisen.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 17).fill(
                    RadialGradient(colors: [.primary.opacity(0.10), .primary.opacity(0.025)],
                                   center: .center, startRadius: 6, endRadius: 225))
            }
            .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(.primary.opacity(0.10)) }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: capture.caps)

            HStack {
                if !listening {
                    Button { capture = ShortcutCapture() } label: { Label("Neu aufnehmen", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(.plain)
                }
                Spacer()
                Button("Abbrechen", action: cancel).keyboardShortcut(.cancelAction)
                Button("Übernehmen") {
                    if let chord = capture.captured { save(.shortcut(chord)) }
                }.keyboardShortcut(.defaultAction).disabled(listening)
            }
        }
        .padding(24).frame(width: 450)
        .background(Color(nsColor: .windowBackgroundColor))
        .background { CaptureEvents(capture: $capture).frame(width: 0, height: 0) }
    }

    private func keycaps(scale: CGFloat) -> some View {
        HStack(spacing: 6 * scale) {
            ForEach(Array(capture.caps.enumerated()), id: \.offset) { _, cap in
                PhysicalKey(symbol: cap.symbol, legend: cap.legend, scale: scale)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(capture.captured?.label ?? capture.caps.map(\.symbol).joined(separator: " "))
    }
}

private struct PhysicalKey: View {
    let symbol: String
    let legend: String?
    var placeholder = false
    var scale: CGFloat = 1
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: 1) {
            if placeholder {
                Image(systemName: symbol).font(.system(size: 29 * scale, weight: .light))
                    .foregroundStyle(.secondary)
            } else {
                Text(symbol).font(.system(size: (symbol.count > 3 ? 17 : 33) * scale, weight: .medium))
                if let legend { Text(legend).font(.system(size: 11 * scale, weight: .semibold)).foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 8 * scale)
        .frame(minWidth: 62 * scale, minHeight: 62 * scale)
        .background {
            RoundedRectangle(cornerRadius: 10 * scale).fill(LinearGradient(
                colors: dark ? [Color(white: 0.31), Color(white: 0.21)] : [.white, Color(white: 0.92)],
                startPoint: .top, endPoint: .bottom))
        }
        .overlay { RoundedRectangle(cornerRadius: 10 * scale).strokeBorder(.white.opacity(dark ? 0.18 : 0.85)) }
        .background {
            RoundedRectangle(cornerRadius: 10 * scale).fill(Color(white: dark ? 0.11 : 0.69))
                .offset(y: 4 * scale).shadow(color: .black.opacity(dark ? 0.4 : 0.12), radius: 4, y: 3)
        }
    }
}

/// AppKit delivers modifier-only transitions through flagsChanged. A local
/// monitor scoped to the key sheet also sees Command shortcuts before menus.
private struct CaptureEvents: NSViewRepresentable {
    @Binding var capture: ShortcutCapture
    func makeNSView(context: Context) -> EventView { EventView() }
    func updateNSView(_ view: EventView, context: Context) {
        view.listen = { event in
            guard capture.captured == nil else { return false }
            capture.handle(event)
            return true
        }
        view.interrupted = { if capture.captured == nil { capture = ShortcutCapture() } }
    }
    static func dismantleNSView(_ view: EventView, coordinator: ()) { view.stop() }

    @MainActor final class EventView: NSView {
        var listen: ((NSEvent) -> Bool)?
        var interrupted: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(lostFocus),
                                                   name: NSWindow.didResignKeyNotification, object: window)
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                guard let self, let window = self.window, window.isKeyWindow,
                      event.window == nil || event.window === window else { return event }
                return self.listen?(event) == true ? nil : event
            }
        }
        @objc private func lostFocus() { interrupted?() }
        func stop() {
            NotificationCenter.default.removeObserver(self)
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }
    }
}
