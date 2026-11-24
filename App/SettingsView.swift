import SwiftUI

struct SettingsView: View {
    @Bindable var engine: MouseEngine
    @State private var part: MousePart = .thumb
    @State private var recording: Input?
    @State private var confirmReset = false
    @Environment(\.colorScheme) private var colorScheme
    private var paper: Color { colorScheme == .dark ? Color(white: 0.105) : Color(white: 0.968) }
    private var surface: Color { colorScheme == .dark ? Color(white: 0.145) : .white }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MX Buddy").font(.custom("Outfit", size: 32).weight(.medium))
                Spacer()
                Button { engine.paused.toggle() } label: {
                    Label(engine.paused ? "Fortsetzen" : "Pausieren", systemImage: engine.paused ? "play.fill" : "pause.fill")
                }.controlSize(.small)
            }
            .padding(.horizontal, 26).padding(.top, 10).padding(.bottom, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !engine.accessibility || !engine.monitoring {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Freigaben für Mausbelegungen", systemImage: "lock.open").font(.headline)
                            if !engine.accessibility { permission("Bedienungshilfen", listen: false) }
                            if !engine.monitoring {
                                permission("Eingabeüberwachung", listen: true)
                                Text("Fehlt MX Buddy in der Liste? Klicke dort auf + und wähle diese App. Aktiviere den Schalter und bestätige „Beenden & erneut öffnen“, wenn macOS danach fragt.")
                                    .font(.callout).foregroundStyle(.secondary)
                                Button("Installierte App im Finder zeigen") {
                                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                                }
                            }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: .rect(cornerRadius: 12))
                    }
                    if let warning = engine.diagnostics[engine.selected] {
                        Label(warning, systemImage: "exclamationmark.triangle").font(.callout)
                        Button("Verbindung erneut prüfen") { engine.refresh(force: true) }
                    }
                    if engine.tapFailed { Text("Klicks und Standard-Scrollereignisse können aktuell nicht umgelegt werden. Bitte prüfe die Bedienungshilfen.") }
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Menu {
                                Picker("Maus", selection: $engine.selected) {
                                    ForEach(MouseModel.allCases) { model in Text(model.rawValue).tag(model) }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(engine.selected.rawValue).font(.custom("Outfit", size: 26).weight(.medium))
                                    Image(systemName: "chevron.down").font(.caption.bold())
                                }
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel("Maus auswählen, " + engine.selected.rawValue)
                            HStack(spacing: 6) {
                                Circle().fill(engine.connected.contains(engine.selected) ? Color.green : Color.secondary)
                                    .frame(width: 6, height: 6)
                                Text(modelStatus).font(.caption).foregroundStyle(.secondary)
                            }
                            MouseDiagram(model: engine.selected, part: $part)
                                .frame(height: 284).padding(.top, 8)
                        }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBackground)
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Bedienelement").font(.subheadline).foregroundStyle(.secondary)
                            Menu {
                                Picker("Bedienelement", selection: $part) {
                                    ForEach(MousePart.available(on: engine.selected)) { Text($0.rawValue).tag($0) }
                                }
                            } label: {
                                HStack {
                                    Text(part.rawValue).font(.custom("Outfit", size: 24).weight(.medium))
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                                }
                            }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                            .accessibilityLabel("Bedienelement auswählen, " + part.rawValue)
                            Divider()
                            BindingEditor(part: part, profile: engine.profiles, model: engine.selected,
                                          assign: { engine.set($1, for: $0) }, record: { recording = $0 })
                                .id(part)

                        }
                        .padding(18).frame(width: 300, alignment: .leading)
                        .background(cardBackground)
                    }
                }.padding(.horizontal, 24).padding(.vertical, 18)
            }
            Divider()
            HStack(alignment: .center) {
                LoginItemSetting()
                Spacer()
                Button("Belegungen zurücksetzen …") { confirmReset = true }
                    .buttonStyle(.plain).font(.caption)
                    .help(engine.rescueAvailable ? "Beide Profile zurücksetzen (⌃⌥⇧R)" : "Beide Profile zurücksetzen")
            }.padding(.horizontal, 26).padding(.vertical, 14)
        }
        .background(paper)
        .onChange(of: engine.selected) { _, model in
            if !MousePart.available(on: model).contains(part) { part = .thumb }
        }
        .alert("Beide Mäuse zurücksetzen?", isPresented: $confirmReset) {
            Button("Abbrechen", role: .cancel) { }
            Button("Zurücksetzen", role: .destructive) { engine.resetAll() }
        } message: { Text("Alle Bedienelemente erhalten ihr natives Verhalten zurück.") }
        .sheet(item: $recording) { input in
            RecorderSheet(input: input) { engine.set($0, for: input); recording = nil } cancel: { recording = nil }
        }
    }

    private func permission(_ name: String, listen: Bool) -> some View {
        HStack { Text(name); Spacer(); Button("Systemeinstellungen öffnen …") { engine.permissions(listen: listen) } }
    }
    private var modelStatus: String {
        guard engine.connected.contains(engine.selected) else { return "Offline" }
        if engine.paused { return "Pausiert" }
        return engine.readyModels.contains(engine.selected) ? "Verbunden · Sondertasten bereit" : "Verbunden"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(surface)
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08)) }
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
