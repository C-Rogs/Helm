import Core
import Persistence
import SwiftUI

#if DEBUG
struct DataBrowserView: View {
    @State private var vitalsDays: [DailyMetricColumn: [HelmDay]] = [:]
    @State private var sleepDays: [HelmDay] = []
    @State private var nutritionDays: [HelmDay] = []
    @State private var bodyCompositionDays: [HelmDay] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("Vitals & activity") {
                ForEach(DailyMetricColumn.allCases, id: \.self) { column in
                    metricRow(column.displayName, days: vitalsDays[column] ?? [])
                }
            }

            Section("Sleep") {
                metricRow("Sleep intervals", days: sleepDays)
            }

            Section("Nutrition") {
                metricRow("Nutrition days", days: nutritionDays)
            }

            Section("Body composition") {
                metricRow("Body mass", days: bodyCompositionDays)
            }
        }
        .navigationTitle("Stored Data")
        .refreshable { await reload() }
        .task { await reload() }
    }

    @ViewBuilder
    private func metricRow(_ title: String, days: [HelmDay]) -> some View {
        if days.isEmpty {
            LabeledContent(title, value: "None")
        } else {
            NavigationLink(title) {
                DayListDetailView(title: title, days: days)
            }
        }
    }

    private func reload() async {
        errorMessage = nil
        do {
            let store = PersistenceBootstrap.persistenceStore
            var loaded: [DailyMetricColumn: [HelmDay]] = [:]
            for column in DailyMetricColumn.allCases {
                loaded[column] = try store.dailyMetrics.listDays(where: column)
            }
            vitalsDays = loaded
            sleepDays = try store.sleep.listDays()
            nutritionDays = try store.nutrition.listDays()
            bodyCompositionDays = try store.bodyComposition.listDays()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DayListDetailView: View {
    let title: String
    let days: [HelmDay]

    var body: some View {
        List(days.reversed(), id: \.self) { day in
            Text(day.formatted)
        }
        .navigationTitle(title)
    }
}
#endif
