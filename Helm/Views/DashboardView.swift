import DesignSystem
import SwiftUI

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                    Gauge(value: 0, label: "ARC", subtitle: "Building baseline 0/4")

                    Card {
                        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                            Text("Today")
                                .font(HelmTypography.headline)
                                .foregroundStyle(HelmColor.textPrimary)
                            StatRow(label: "Readiness", value: "N/A", detail: "Awaiting data")
                            StatRow(label: "Training", value: "N/A")
                        }
                    }

                    Button("Ask Coach") {}
                        .buttonStyle(.helmPrimary)
                }
                .padding(HelmSpacing.md)
            }
            .helmScreenBackground()
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    DashboardView()
        .helmTheme()
}
