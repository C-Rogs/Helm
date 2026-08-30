import DesignSystem
import SwiftUI

struct CalendarHintStatusView: View {
    @State private var status = CalendarAuthorizationStatus.notDetermined
    @State private var isRequesting = false
    @State private var errorMessage: String?

    private let service = CalendarHintBootstrap.service

    var body: some View {
        List {
            Section {
                Text(
                    "Signal reads your calendar to flag busy days on the week-ahead schedule. "
                        + "Events are never written back."
                )
                .helmType(.body, color: HelmColor.fgSecondary)
                .helmListRowChrome()
            }

            Section("Status") {
                HelmStatusRow(
                    label: "Access",
                    value: statusLabel,
                    valueColor: status == .authorized ? HelmColor.ready : HelmColor.fgMuted
                )
                .helmListRowChrome()
            }

            if let errorMessage {
                Section("Error") {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .helmType(.body, color: HelmColor.depleted)
                        .helmListRowChrome()
                }
            }

            Section {
                if status != .authorized {
                    Button(isRequesting ? "Requesting…" : "Allow Calendar Access") {
                        Task { await requestAccess() }
                    }
                    .disabled(isRequesting || status == .restricted)
                    .helmListRowChrome()
                }

                if status == .denied {
                    Text("Open Settings → Privacy & Security → Calendars to change access.")
                        .helmType(.body, color: HelmColor.fgMuted)
                        .helmListRowChrome()
                }
            }
        }
        .helmSettingsListChrome()
        .navigationTitle("Calendar Hints")
        .task {
            status = service.currentStatus()
        }
    }

    private var statusLabel: String {
        switch status {
        case .notDetermined:
            "Not requested"
        case .restricted:
            "Restricted"
        case .denied:
            "Denied"
        case .authorized:
            "Allowed"
        }
    }

    private func requestAccess() async {
        isRequesting = true
        errorMessage = nil
        status = await service.requestAccess()
        if status == .denied {
            errorMessage = "Calendar access was denied."
        }
        isRequesting = false
        HapticEngine.shared.play(.selection)
    }
}

#if DEBUG
#Preview("Calendar hints settings") {
    NavigationStack {
        CalendarHintStatusView()
    }
    .helmTheme()
}
#endif
