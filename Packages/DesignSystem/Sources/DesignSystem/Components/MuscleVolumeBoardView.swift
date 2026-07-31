import SwiftUI

public struct MuscleVolumeBoardView: View {
    private let model: MuscleVolumeBoardModel
    private let showsHeader: Bool
    private let rankedRows: [MuscleVolumeBoardRow]

    public init(model: MuscleVolumeBoardModel, showsHeader: Bool = true, limit: Int? = nil) {
        self.model = model
        self.showsHeader = showsHeader
        if let limit {
            rankedRows = Array(model.rows.prefix(limit))
        } else {
            rankedRows = model.rows
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            if showsHeader {
                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    Text(MuscleVolumeBoardModel.loadWindowTitle)
                        .helmType(.title)
                    Text(MuscleVolumeBoardModel.loadWindowSubtitle)
                        .helmType(.body, color: HelmColor.fgSecondary)
                }
            }

            if rankedRows.isEmpty {
                Text("Log training in the last 7 days to see per-muscle volume.")
                    .helmType(.body, color: HelmColor.fgMuted)
                    .frame(maxWidth: .infinity, minHeight: HelmLayout.emptyChartMinHeight, alignment: .leading)
            } else {
                VStack(spacing: HelmSpacing.md) {
                    ForEach(rankedRows) { row in
                        LandmarkVolumeBar(
                            label: row.label,
                            weeklySets: row.weeklySets,
                            mev: row.mev,
                            mrv: row.mrv,
                            state: row.state,
                            daysSinceTrained: row.daysSinceTrained,
                            showsRecency: true
                        )
                    }
                }

                Text("Shaded band is MEV to MRV")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        }
    }
}

public struct MuscleVolumeSummaryCard: View {
    private let model: MuscleVolumeBoardModel

    public init(model: MuscleVolumeBoardModel) {
        self.model = model
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HStack {
                    HelmSectionEyebrow("MUSCLE VOLUME")
                    Spacer()
                    HelmIconView(.chevronRight, context: .inline)
                        .foregroundStyle(HelmColor.fgMuted)
                }

                if model.summaryRows.isEmpty {
                    Text("Log training to track 7-day volume against landmarks.")
                        .helmType(.body, color: HelmColor.fgMuted)
                } else {
                    VStack(spacing: HelmSpacing.sm) {
                        ForEach(model.summaryRows) { row in
                            LandmarkVolumeBar(
                                label: row.label,
                                weeklySets: row.weeklySets,
                                mev: row.mev,
                                mrv: row.mrv,
                                state: row.state,
                                daysSinceTrained: row.daysSinceTrained,
                                showsRecency: true
                            )
                        }
                    }

                    if model.rows.count > model.summaryRows.count {
                        Text("\(model.rows.count - model.summaryRows.count) more muscles")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Muscle volume board states") {
    ScrollView {
        MuscleVolumeBoardView(model: .stateCoverageFixture)
            .padding()
    }
    .helmTheme()
}

#Preview("Muscle volume board data sheet") {
    ScrollView {
        MuscleVolumeBoardView(model: .stateCoverageFixture)
            .padding()
    }
    .helmTheme()
    .environment(\.helmSkin, .dataSheet)
}

#Preview("Muscle volume summary") {
    MuscleVolumeSummaryCard(model: .stateCoverageFixture)
        .padding()
        .helmTheme()
}

#Preview("Muscle volume summary data sheet") {
    MuscleVolumeSummaryCard(model: .stateCoverageFixture)
        .padding()
        .helmTheme()
        .environment(\.helmSkin, .dataSheet)
}

#Preview("Muscle volume empty") {
    MuscleVolumeSummaryCard(model: .emptyFixture)
        .padding()
        .helmTheme()
}
#endif
