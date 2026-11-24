import AppKit
import ApplicationServices
import IOKit.hid
import Observation

@MainActor @Observable
final class MouseEngine {
    static let shared = MouseEngine()
    var selected: MouseModel = .three
    private(set) var profiles: Profiles
    var paused: Bool {
        didSet {
            UserDefaults.standard.set(paused, forKey: "paused")
            refresh(force: true)
        }
    }
    private(set) var accessibility = false
    private(set) var monitoring = false
    private(set) var connected: Set<MouseModel> = []
    private(set) var diagnostics: [MouseModel: String] = [:]
    private(set) var tapFailed = false
    var rescueAvailable = false
    @ObservationIgnored private var manager: IOHIDManager?
    @ObservationIgnored private var sessions: [UInt64: LogitechSession] = [:]
    @ObservationIgnored private var deviceSources: [UInt64: Set<UInt64>] = [:]
    @ObservationIgnored private var senders: [UInt64: MouseModel] = [:]
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private var retry: [UInt64: Date] = [:]
    @ObservationIgnored private var router = MouseEventRouter()
    @ObservationIgnored private var sleeping = false
    @ObservationIgnored private var initializedSelection = false

    private init() {
        profiles = UserDefaults.standard.data(forKey: "profiles.v1").flatMap {
            try? JSONDecoder().decode(Profiles.self, from: $0)
        } ?? Profiles()
        paused = UserDefaults.standard.bool(forKey: "paused")
    }

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x046D, kIOHIDPrimaryUsagePageKey: 1,
                                               kIOHIDPrimaryUsageKey: 2] as CFDictionary)
        self.manager = manager
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        refresh()
        poll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated { MouseEngine.shared.refresh() }
        }
    }

    func set(_ action: Action, for input: Input) {
        profiles[selected, input] = action
        save()
    }

    func resetAll() {
        for model in MouseModel.allCases { profiles.restoreNative(model) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "profiles.v1") }
        for session in sessions.values { session.configure(profiles) }
    }

    func sleep() { sleeping = true; refresh(force: true) }
    func wake() { sleeping = false; refresh(force: true) }
    func stop() {
        poll?.invalidate()
        sleep()
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
        manager = nil
    }

    func permissions(listen: Bool) {
        if listen { _ = CGRequestListenEventAccess() }
        else { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }
        let pane = listen ? "ListenEvent" : "Accessibility"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane) {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh(force: Bool = false) {
        accessibility = AXIsProcessTrusted()
        monitoring = CGPreflightListenEventAccess()
        let active = !paused && !sleeping && accessibility && monitoring
        if force || (!active && (tap != nil || !sessions.isEmpty || tapFailed)) {
            for id in Array(sessions.keys) { remove(id) }
            removeTap()
            retry = [:]
            diagnostics = [:]
        }
        if active && tap == nil { installTap() }
        guard let manager else { return }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        var attached: Set<UInt64> = [], models: Set<MouseModel> = [], sources: [UInt64: MouseModel] = [:]
        for device in devices {
            let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
            guard let model = MouseModel(product: name) else { continue }
            let service = IOHIDDeviceGetService(device)
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { continue }
            // A mouse has a stable registry subtree for the lifetime of this connection.
            if deviceSources[id] == nil {
                var ids: Set<UInt64> = [id]
                var iterator: io_iterator_t = 0
                if IORegistryEntryCreateIterator(service, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS {
                    while true {
                        let child = IOIteratorNext(iterator)
                        if child == 0 { break }
                        var childID: UInt64 = 0
                        if IORegistryEntryGetRegistryEntryID(child, &childID) == KERN_SUCCESS { ids.insert(childID) }
                        IOObjectRelease(child)
                    }
                    IOObjectRelease(iterator)
                }
                if ids.count > 1 { deviceSources[id] = ids }
                for sender in ids { sources[sender] = model }
            } else {
                for sender in deviceSources[id] ?? [] { sources[sender] = model }
            }
            models.insert(model)
            attached.insert(id)
            guard active, tap != nil else { continue }
            if sessions[id] == nil {
                if let later = retry[id], later > Date() { continue }
                guard IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else {
                    diagnostics[model] = "Mauszugriff fehlgeschlagen. Eingabeüberwachung und Logi Options+ prüfen."
                    retry[id] = Date().addingTimeInterval(15)
                    continue
                }
                let session = LogitechSession(transport: BluetoothTransport(device), model: model)
                sessions[id] = session
                session.onInput = { [weak self] input in self?.perform(input, model) }
                session.onStatus = { [weak self] message in
                    self?.diagnostics[model] = message
                    self?.retry[id] = message == nil ? nil : Date().addingTimeInterval(20)
                }
                session.configure(profiles)
            } else if let later = retry[id], later <= Date() {
                retry[id] = nil
                sessions[id]?.configure(profiles)
            }
        }
        for id in sessions.keys.filter({ !attached.contains($0) }) { remove(id) }
        deviceSources = deviceSources.filter { attached.contains($0.key) }
        senders = sources
        if connected != models { connected = models }
        if !initializedSelection, let first = MouseModel.allCases.first(where: models.contains) {
            selected = first
            initializedSelection = true
        }
    }

    private func remove(_ id: UInt64) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.close()
        retry[id] = nil
        diagnostics[session.model] = nil
    }

    private func installTap() {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown,
            .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
        let mask = types.reduce(UInt64(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                               eventsOfInterest: mask, callback: { _, type, event, _ in
            let suppress = MainActor.assumeIsolated {
                let engine = MouseEngine.shared
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = engine.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return false
                }
                return engine.filter(type, event)
            }
            return suppress ? nil : Unmanaged.passUnretained(event)
        }, userInfo: nil)
        tapFailed = tap == nil
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        router = MouseEventRouter()
        tapFailed = false
    }

    private func filter(_ type: CGEventType, _ event: CGEvent) -> Bool {
        // Quartz field 87 is the originating IORegistry service ID. Unknown sources pass through.
        let quartz = UInt64(bitPattern: event.getIntegerValueField(CGEventField(rawValue: 87)!))
        let sender = quartz == 0 ? HIDSender.id(of: event) ?? 0 : quartz
        return router.filter(type: type, event: event, sender: sender, sources: senders,
                             profiles: profiles, perform: perform)
    }

    private func perform(_ input: Input, _ model: MouseModel) {
        guard !paused, !sleeping else { return }
        let code: CGKeyCode, flags: CGEventFlags
        switch profiles[model, input] {
        case .native: return
        case .spaceLeft: code = 123; flags = .maskControl
        case .spaceRight: code = 124; flags = .maskControl
        case .missionControl: code = 126; flags = .maskControl
        case .shortcut(let chord): code = chord.code; flags = CGEventFlags(rawValue: chord.flags)
        }
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}

// Newer WindowServer versions sometimes leave the Quartz sender field empty.
// Resolve the underlying HID event only when both optional system symbols exist.
private enum HIDSender {
    typealias CopyEvent = @convention(c) (CGEvent) -> Unmanaged<CFTypeRef>?
    typealias SenderID = @convention(c) (CFTypeRef) -> UInt64
    static let copyEvent: CopyEvent? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventCopyIOHIDEvent").map {
        unsafeBitCast($0, to: CopyEvent.self)
    }
    static let senderID: SenderID? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOHIDEventGetSenderID").map {
        unsafeBitCast($0, to: SenderID.self)
    }

    static func id(of event: CGEvent) -> UInt64? {
        guard let senderID, let backing = copyEvent?(event)?.takeRetainedValue() else { return nil }
        return senderID(backing)
    }
}
