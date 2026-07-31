import CoachLLM
import Core
import HealthKitIngest
import Persistence
import SwiftUI

#if DEBUG
struct InSessionCoachDebugView: View {
    @Bindable private var sessionController = TrainBootstrap.sessionController
    @State private var recommendations: [StoredCoachRecommendation] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("Context preview") {
                if let snapshot = sessionController.snapshot {
                    let exerciseIDs = snapshot.session.exercises.map(\.exerciseID)
                    let displayNames = (try? PersistenceBootstrap.persistenceStore.exercises
                        .displayNames(for: exerciseIDs)) ?? [:]
                    Text(
                        InSessionCoachContextBuilder.sessionExerciseBlock(
                            snapshot: snapshot,
                            displayNames: displayNames,
                            importContextNotes: InSessionCoachContextBuilder.importContextNotes(
                                from: snapshot.session.notes
                            )
                        )
                    )
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                } else {
                    Text("Start a workout to preview coach context.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Correlation") {
                if let requestID = sessionController.lastCoachRequestID {
                    LabeledContent("Last Gemini requestID", value: requestID.uuidString)
                } else {
                    LabeledContent("Last Gemini requestID", value: "None this session")
                }
                if let snapshot = sessionController.snapshot {
                    LabeledContent("Active session", value: snapshot.session.id)
                } else {
                    LabeledContent("Active session", value: "None")
                }
            }

            Section("Last failure") {
                LabeledContent("Surface", value: CoachDiagnosticsStore.shared.lastSurface ?? "None")
                LabeledContent("Error code", value: CoachDiagnosticsStore.shared.lastErrorCode ?? "None")
                LabeledContent("Request ID", value: CoachDiagnosticsStore.shared.lastRequestID ?? "None")
                if let rejectReason = CoachDiagnosticsStore.shared.lastRejectReason {
                    LabeledContent("Reject reason", value: rejectReason)
                }
            }

            Section("Ephemeral chat (this workout)") {
                if sessionController.coachMessages.isEmpty {
                    Text("No in-session coach messages yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessionController.coachMessages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role == .user ? "You" : "Coach")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(message.text)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Stored recommendations") {
                if recommendations.isEmpty {
                    Text("No coach_recommendation rows for this session.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recommendations) { row in
                        NavigationLink {
                            CoachRecommendationDetailView(recommendation: row)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.generatedAt.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption)
                                Text(statusLabel(for: row))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("In-Session Coach")
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func statusLabel(for row: StoredCoachRecommendation) -> String {
        if row.actedOnAt != nil { return "Applied" }
        if row.dismissedAt != nil { return "Dismissed" }
        return "Proposed"
    }

    private func reload() async {
        errorMessage = nil
        guard let sessionID = sessionController.snapshot?.session.id else {
            recommendations = []
            return
        }
        do {
            recommendations = try PersistenceBootstrap.persistenceStore.coachRecommendations
                .fetchForSession(sessionID: sessionID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CoachRecommendationDetailView: View {
    let recommendation: StoredCoachRecommendation

    private var decodedPayload: SessionAdjustmentPayload? {
        guard let data = recommendation.payloadJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SessionAdjustmentPayload.self, from: data)
    }

    var body: some View {
        List {
            Section("Metadata") {
                LabeledContent("ID", value: recommendation.id)
                LabeledContent("Model", value: recommendation.modelVersion ?? "n/a")
                LabeledContent("Generated", value: recommendation.generatedAt.formatted())
                LabeledContent("Acted on", value: recommendation.actedOnAt?.formatted() ?? "n/a")
                LabeledContent("Dismissed", value: recommendation.dismissedAt?.formatted() ?? "n/a")
            }

            if let payload = decodedPayload {
                Section("Reply") {
                    Text(payload.reply)
                        .textSelection(.enabled)
                }

                if let rationale = payload.rationale, !rationale.isEmpty {
                    Section("Rationale") {
                        Text(rationale)
                            .textSelection(.enabled)
                    }
                }

                Section("Operations (\(payload.operations.count))") {
                    if payload.operations.isEmpty {
                        Text("Advisory only")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(describing: payload.operations))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            } else {
                Section("Payload") {
                    Text(recommendation.payloadJSON)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Recommendation")
    }
}
#endif
