import DesignSystem
import HealthKitIngest
import ReadinessKit
import SwiftUI

struct DashboardView: View {
    private var readinessService: ReadinessService { ReadinessBootstrap.readinessService }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                    greetingHeader
                    readinessCard

                    Button {
                    } label: {
                        Label("Ask Coach", systemImage: "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(.helmSecondary)
                }
                .padding(HelmSpacing.md)
            }
            .helmScreenBackground()
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await readinessService.refresh()
            }
        }
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(greetingText)
                .font(HelmTypography.title)
                .foregroundStyle(HelmColor.textPrimary)
            Text("Today's readiness")
                .font(HelmTypography.callout)
                .foregroundStyle(HelmColor.textSecondary)
        }
    }

    @ViewBuilder
    private var readinessCard: some View {
        switch readinessService.state {
        case .loading:
            readinessShell(subtitle: "Loading…") {
                Gauge(value: 0, label: "ARC", subtitle: "Loading…")
            }
        case .awaitingData:
            readinessShell(subtitle: "Awaiting data") {
                Gauge(value: 0, label: "ARC", subtitle: "Awaiting data")
            }
        case let .buildingBaseline(_, message):
            readinessShell(subtitle: message) {
                Gauge(value: 0, label: "ARC", subtitle: message)
            }
        case let .scored(score):
            readinessShell(subtitle: readinessSubtitle(for: score), band: score.band) {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    Gauge(
                        value: Double(score.score),
                        label: "ARC",
                        subtitle: nil
                    )
                    .frame(maxWidth: 220)
                    .frame(maxWidth: .infinity)

                    contributorsCard(for: score)
                }
            }
        }
    }

    private func readinessShell<Content: View>(
        subtitle: String,
        band: ReadinessBand? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HStack {
                    Text("ARC")
                        .font(HelmTypography.headline)
                        .foregroundStyle(HelmColor.textPrimary)
                    Spacer()
                    if let band {
                        bandBadge(for: band)
                    }
                }

                content()

                Text(subtitle)
                    .font(HelmTypography.callout)
                    .foregroundStyle(HelmColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .overlay(alignment: .top) {
            if let band {
                RoundedRectangle(cornerRadius: HelmRadius.md)
                    .fill(bandColor(for: band))
                    .frame(height: 3)
                    .padding(.horizontal, 1)
            }
        }
    }

    private func contributorsCard(for score: ReadinessScore) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HStack {
                Text("Contributors")
                    .font(HelmTypography.headline)
                    .foregroundStyle(HelmColor.textPrimary)
                Spacer()
                Text(confidenceLabel(for: score.confidence))
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.textSecondary)
            }

            contributorBar("HRV", z: score.contributors.zHRV)
            contributorBar("Resting HR", z: score.contributors.zRestingHR)
            contributorBar("Sleep", z: score.contributors.zSleep)
            if score.contributors.zStrain != nil {
                contributorBar("Strain", z: score.contributors.zStrain)
            }
            if score.contributors.zRespiratory != nil {
                contributorBar("Respiratory", z: score.contributors.zRespiratory)
            }
            if score.contributors.zTemperature != nil {
                contributorBar("Temperature", z: score.contributors.zTemperature)
            }
        }
    }

    private func bandBadge(for band: ReadinessBand) -> some View {
        Text(band.rawValue.capitalized)
            .font(HelmTypography.caption)
            .foregroundStyle(bandColor(for: band))
            .padding(.horizontal, HelmSpacing.xs)
            .padding(.vertical, HelmSpacing.xxs)
            .background(bandColor(for: band).opacity(0.15), in: Capsule())
    }

    private func bandColor(for band: ReadinessBand) -> Color {
        switch band {
        case .depleted: HelmColor.warning
        case .balanced: HelmColor.accent
        case .primed: HelmColor.positive
        }
    }

    private func contributorBar(_ label: String, z: Double?) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            HStack {
                Text(label)
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.textSecondary)
                Spacer()
                Text(contributorValueText(z))
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.textPrimary)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(HelmColor.gaugeTrack)
                    Capsule()
                        .fill(contributorFillColor(z))
                        .frame(width: geometry.size.width * contributorFillFraction(z))
                }
            }
            .frame(height: 6)

            if let detail = contributorDetail(z) {
                Text(detail)
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.textTertiary)
            }
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5 ..< 12: return "Good morning"
        case 12 ..< 17: return "Good afternoon"
        case 17 ..< 22: return "Good evening"
        default: return "Good night"
        }
    }

    private func readinessSubtitle(for score: ReadinessScore) -> String {
        if score.validNights < 14 {
            return "Provisional baseline (\(score.validNights)/14 nights)"
        }
        return "\(score.band.rawValue.capitalized) · \(confidenceLabel(for: score.confidence))"
    }

    private func confidenceLabel(for confidence: ReadinessConfidence) -> String {
        switch confidence {
        case .high: "High confidence"
        case .medium: "Medium confidence"
        case .low: "Low confidence"
        }
    }

    private func contributorValueText(_ z: Double?) -> String {
        guard let z else { return "N/A" }
        let sign = z >= 0 ? "+" : ""
        return "z \(sign)\(String(format: "%.1f", z))"
    }

    private func contributorFillFraction(_ z: Double?) -> CGFloat {
        guard let z else { return 0 }
        let clamped = min(max(z, -2), 2)
        return CGFloat((clamped + 2) / 4)
    }

    private func contributorFillColor(_ z: Double?) -> Color {
        guard let z else { return HelmColor.textTertiary }
        if z > 0.75 { return HelmColor.positive }
        if z < -0.75 { return HelmColor.warning }
        return HelmColor.accent
    }

    private func contributorDetail(_ z: Double?) -> String? {
        guard let z else { return "No data" }
        if z > 0.75 { return "Above baseline" }
        if z < -0.75 { return "Below baseline" }
        return "Near baseline"
    }
}

#Preview {
    DashboardView()
        .helmTheme()
}
