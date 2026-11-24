import SwiftUI
import Carbon.HIToolbox

@main
struct MXBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra("MX Buddy", systemImage: "computermouse") {
            Button("Belegungen öffnen …") { delegate.showWindow() }
                .keyboardShortcut(",")
            Button(MouseEngine.shared.paused ? "Belegungen fortsetzen" : "Belegungen pausieren") {
                MouseEngine.shared.paused.toggle()
            }
            Divider()
            Button("MX Buddy beenden") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var rescueKey: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "Outfit", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        MouseEngine.shared.start()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sleepNow), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(wakeNow), name: NSWorkspace.didWakeNotification, object: nil)
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var key = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &key) == noErr,
                  key.signature == 0x4D584255, key.id == 1 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { MouseEngine.shared.resetAll() }
            return noErr
        }, 1, &type, nil, nil)
        let keyStatus = RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey | shiftKey),
                            EventHotKeyID(signature: 0x4D584255, id: 1), GetApplicationEventTarget(), 0, &rescueKey)
        MouseEngine.shared.rescueAvailable = keyStatus == noErr
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == keyAELaunchedAsLogInItem
        if !loginLaunch { showWindow() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MouseEngine.shared.refresh()
    }

    @objc private func sleepNow() { MouseEngine.shared.sleep() }
    @objc private func wakeNow() { MouseEngine.shared.wake() }
    func applicationWillTerminate(_ notification: Notification) {
        if let rescueKey { UnregisterEventHotKey(rescueKey) }
        MouseEngine.shared.stop()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func showWindow() {
        if window == nil {
            let view = SettingsView(engine: .shared)
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 888, height: 552),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                 backing: .buffered, defer: false)
            panel.title = "MX Buddy"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 760, height: 440)
            panel.contentView = NSHostingView(rootView: view)
            panel.setFrameAutosaveName("MX Buddy Mausansicht")
            if !panel.setFrameUsingName("MX Buddy Mausansicht") { panel.center() }
            window = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
