import SwiftUI

struct SettingsView: View {
    @Bindable var engine: MouseEngine
    @State private var showDirections = false
    @State private var showMain = false
    @State private var recording: Input?
    @State private var confirmReset = false
    @Environment(\.colorScheme) private var colorScheme
    private var paper: Color { colorScheme == .dark ? Color(white: 0.105) : Color(white: 0.968) }
    private var surface: Color { colorScheme == .dark ? Color(white: 0.145) : .white }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MX Buddy").font(.custom("Outfit", size: 34).weight(.medium))
                    Text(engine.paused ? "Belegungen pausiert" : "Mausbelegungen").foregroundStyle(.secondary)
                }
                Spacer()
                Button { engine.paused.toggle() } label: {
                    Image(systemName: engine.paused ? "play.fill" : "pause.fill").frame(width: 22, height: 20)
                }
                .accessibilityLabel(engine.paused ? "Belegungen fortsetzen" : "Belegungen pausieren")
                .help(engine.paused ? "Belegungen fortsetzen" : "Belegungen pausieren")
            }
            .padding(.horizontal, 26).padding(.top, 12).padding(.bottom, 18)
            HStack {
                Picker("Maus", selection: $engine.selected) {
                    ForEach(MouseModel.allCases) { model in Text(model.rawValue).tag(model) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 245)
                Spacer()
                let online = engine.connected.contains(engine.selected)
                Label(online ? "Verbunden" : "Offline", systemImage: online ? "link" : "link.badge.plus")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 26).padding(.bottom, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !engine.accessibility || !engine.monitoring {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Freigaben für Mausbelegungen", systemImage: "lock.open").font(.headline)
                            if !engine.accessibility { permission("Bedienungshilfen", listen: false) }
                            if !engine.monitoring { permission("Eingabeüberwachung", listen: true) }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: .rect(cornerRadius: 12))
                    }
                    if let warning = engine.diagnostics[engine.selected] {
                        Label(warning, systemImage: "exclamationmark.triangle").font(.callout)
                        Button("Verbindung erneut prüfen") { engine.refresh(force: true) }
                    }
                    if engine.tapFailed { Text("Der Ereignisfilter ist inaktiv. Bitte prüfe die Freigaben und öffne MX Buddy erneut.") }
                    group("Daumen", symbol: "hand.point.up.left") {
                        row(.thumbLeft)
                        row(.thumbRight)
                        row(.gesture)
                        DisclosureGroup("Beim Halten bewegen", isExpanded: $showDirections) {
                            ForEach(Input.directions) { row($0) }
                        }.padding(.horizontal, 12).padding(.vertical, 8)
                        if engine.selected == .four { row(.panel) }
                    }
                    group("Maustasten", symbol: "computermouse") {
                        ForEach([Input.back, .forward, .middle, .mode]) { row($0) }
                    }
                    DisclosureGroup("Haupttasten und Scrollrad", isExpanded: $showMain) {
                        ForEach([Input.left, .right, .wheelUp, .wheelDown]) { row($0) }
                    }.padding(14).background(surface, in: .rect(cornerRadius: 12))
                }.padding(.horizontal, 26).padding(.vertical, 18)
            }
            Divider()
            HStack {
                Button("Alle Belegungen zurücksetzen …") { confirmReset = true }
                    .buttonStyle(.plain)
                Spacer()
                Text(engine.rescueAvailable ? "⌃⌥⇧R" : "Rücksetz-Kürzel nicht verfügbar")
                    .foregroundStyle(.secondary).help("Systemweit das native Mausverhalten wiederherstellen")
            }.font(.caption).padding(.horizontal, 26).padding(.vertical, 12)
        }
        .background(paper)
        .tint(.primary)
        .alert("Beide Mäuse zurücksetzen?", isPresented: $confirmReset) {
            Button("Abbrechen", role: .cancel) { }
            Button("Zurücksetzen", role: .destructive) { engine.resetAll() }
        } message: { Text("Alle Bedienelemente erhalten ihr natives Verhalten zurück.") }
        .sheet(item: $recording) { input in
            RecorderSheet(input: input) { engine.set($0, for: input); recording = nil } cancel: { recording = nil }
        }
    }

    private func permission(_ name: String, listen: Bool) -> some View {
        HStack { Text(name); Spacer(); Button("Freigeben …") { engine.permissions(listen: listen) } }
    }
    private func group<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.custom("Outfit", size: 17).weight(.medium))
            VStack(spacing: 0) { content() }.background(surface, in: .rect(cornerRadius: 12))
        }
    }

    private func row(_ input: Input) -> some View {
        let current = engine.profiles[engine.selected, input]
        let gestureOwned = Input.gestureFamily.contains(input) && Input.gestureFamily.contains {
            engine.profiles[engine.selected, $0] != .native
        }
        let nativeLabel = gestureOwned ? "Unbelegt" : Action.native.label
        return HStack {
            Text(input.label)
            Spacer()
            Menu {
                ForEach([Action.native, .spaceLeft, .spaceRight, .missionControl], id: \.self) { action in
                    Button {
                        engine.set(action, for: input)
                    } label: {
                        let label = action == .native ? nativeLabel : action.label
                        if action == current { Label(label, systemImage: "checkmark") } else { Text(label) }
                    }
                }
                Divider()
                Button("Eigenes Tastenkürzel …") { recording = input }
            } label: { Text(current == .native ? nativeLabel : current.label) }
            .fixedSize().accessibilityLabel(input.label + ", " + current.label)
        }
        .padding(.horizontal, 12).frame(minHeight: 36)
    }
}

private struct RecorderSheet: View {
    let input: Input
    let save: (Action) -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Text(input.label).font(.title2)
            Text("Drücke das gewünschte Tastenkürzel.").foregroundStyle(.secondary)
            Recorder(save: { save(.shortcut($0)) }, cancel: cancel).frame(width: 1, height: 1)
            Button("Abbrechen", action: cancel)
        }.padding(30)
    }
}
private struct Recorder: NSViewRepresentable {
    let save: (Chord) -> Void
    let cancel: () -> Void
    func makeNSView(context: Context) -> KeyView { KeyView(save: save, cancel: cancel) }
    func updateNSView(_ nsView: KeyView, context: Context) { }
    final class KeyView: NSView {
        let save: (Chord) -> Void, cancel: () -> Void
        init(save: @escaping (Chord) -> Void, cancel: @escaping () -> Void) {
            self.save = save; self.cancel = cancel
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(self) }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { keyDown(with: event); return true }
        override func keyDown(with event: NSEvent) {
            guard !event.isARepeat else { return }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.keyCode == 53 && flags.isEmpty { cancel(); return }
            let symbols: [(NSEvent.ModifierFlags, String)] = [(.control,"⌃"),(.option,"⌥"),(.shift,"⇧"),(.command,"⌘")]
            let special: [UInt16: String] = [123:"←",124:"→",125:"↓",126:"↑",36:"↩",48:"⇥",49:"Leertaste",51:"⌫",53:"⎋"]
            var key = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
            if let scalar = key.unicodeScalars.first, (0xF704...0xF726).contains(scalar.value) {
                key = "F" + String(scalar.value - 0xF703)
            }
            if key.isEmpty { key = "Taste " + String(event.keyCode) }
            save(Chord(code: event.keyCode, flags: UInt64(flags.rawValue),
                       label: symbols.filter { flags.contains($0.0) }.map(\.1).joined() + key))
        }
    }
}
