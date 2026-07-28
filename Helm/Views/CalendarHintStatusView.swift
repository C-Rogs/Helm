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
                    "Helm reads your calendar to flag busy days on the week-ahead schedule. "
                        + "Events are never written back."
                )
                .helmType(.body, color: HelmColor.fgSecondary)
            }

            Section("Status") {
                LabeledContent("Access", value: statusLabel)
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                if status != .authorized {
                    Button(isRequesting ? "Requesting…" : "Allow Calendar Access") {
                        Task { await requestAccess() }
                    }
                    .disabled(isRequesting || status == .restricted)
                }

                if status == .denied {
                    Text("Open Settings → Privacy & Security → Calendars to change access.")
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
        }
        .listStyle(.plain)
        .listRowBackground(HelmColor.surface)
        .navigationTitle("Calendar Hints")
        .helmScreenBackground()
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
