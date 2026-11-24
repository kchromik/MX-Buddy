import ServiceManagement
import SwiftUI

struct LoginItemSetting: View {
    @State private var status = SMAppService.mainApp.status
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Bei der Anmeldung starten", isOn: Binding(
                get: { status == .enabled || status == .requiresApproval },
                set: update
            )).toggleStyle(.switch).controlSize(.small)
            if status == .requiresApproval {
                Button("In Anmeldeobjekten erlauben …") { SMAppService.openSystemSettingsLoginItems() }
                    .font(.caption)
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { status = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
    }

    private func update(_ enable: Bool) {
        failure = nil
        do {
            if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            failure = "Anmeldeobjekt konnte nicht geändert werden. " + error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}
