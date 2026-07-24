import DesignSystem
import HealthKitIngest
import PhotosUI
import SwiftUI

struct NutritionView: View {
    private var nutritionService: NutritionService { NutritionBootstrap.nutritionService }
    private var prescriptionService: PrescriptionService { PlanBootstrap.prescriptionService }
    @Bindable private var chatController = ChatBootstrap.controller
    @State private var photoMealController = PhotoMealController()
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                HelmScreenStack {
                    photoLogSection

                    switch nutritionService.state {
                    case .loading:
                        loadingCard
                    case let .ready(snapshot):
                        NutritionDaySummaryCard(
                            snapshot: snapshot,
                            showTrend: true,
                            explainMetric: ExplainableMetricMappers.nutrition(
                                snapshot,
                                coachAvailable: chatController.isCoachAvailable
                            ),
                            onAskCoach: chatController.requestCoachHandoff(prompt:)
                        )
                    }
                }
                .helmScreenPadding()
            }
            .helmScreenBackground()
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshTargets() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
            .task {
                await refreshTargets()
            }
            .onChange(of: prescriptionService.state) { _, newState in
                Task {
                    await nutritionService.refresh(prescriptionSummary: newState.summary)
                }
            }
            .onChange(of: photoMealController.pickerItem) { _, _ in
                Task {
                    await photoMealController.handlePickerItemChange()
                }
            }
            .sheet(isPresented: photoConfirmBinding) {
                if case let .confirm(estimate, previewImage) = photoMealController.phase {
                    PhotoMealConfirmSheet(
                        controller: photoMealController,
                        initialEstimate: estimate,
                        previewImage: previewImage
                    )
                }
            }
            .sheet(isPresented: $photoMealController.showsCamera) {
                CameraImagePicker { image in
                    Task {
                        await photoMealController.handleCameraImage(image)
                    }
                }
                .ignoresSafeArea()
            }
            .alert(
                "Meal logging",
                isPresented: photoErrorBinding,
                actions: {
                    Button("OK", role: .cancel) {
                        photoMealController.dismissError()
                    }
                },
                message: {
                    if case let .failed(message) = photoMealController.phase {
                        Text(message)
                    }
                }
            )
        }
    }

    @MainActor
    private func refreshTargets() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await nutritionService.refresh(
            prescriptionSummary: prescriptionService.state.summary
        )
    }

    @ViewBuilder
    private var photoLogSection: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                Text("Log from photo")
                    .helmType(.label)

                if photoMealController.isAvailable {
                    HStack(spacing: HelmSpacing.sm) {
                        PhotosPicker(
                            selection: $photoMealController.pickerItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Choose photo", systemImage: "photo.on.rectangle")
                                .font(HelmTypography.headline)
                                .foregroundStyle(HelmColor.buttonSecondaryForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, HelmSpacing.sm)
                                .background(
                                    HelmColor.buttonSecondaryBackground,
                                    in: RoundedRectangle(cornerRadius: HelmRadius.sm)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: HelmRadius.sm)
                                        .strokeBorder(HelmColor.buttonSecondaryBorder, lineWidth: 1)
                                }
                        }

                        Button {
                            photoMealController.showsCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera.fill")
                                .font(HelmTypography.headline)
                                .foregroundStyle(HelmColor.buttonSecondaryForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, HelmSpacing.sm)
                                .background(
                                    HelmColor.buttonSecondaryBackground,
                                    in: RoundedRectangle(cornerRadius: HelmRadius.sm)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: HelmRadius.sm)
                                        .strokeBorder(HelmColor.buttonSecondaryBorder, lineWidth: 1)
                                }
                        }
                    }

                    if photoMealController.isBusy {
                        HStack(spacing: HelmSpacing.sm) {
                            ProgressView()
                            Text(photoMealController.busyMessage)
                                .helmType(.body, color: HelmColor.fgMuted)
                        }
                    }
                } else {
                    Text("Add your Gemini API key in Settings to estimate meals from photos.")
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
        }
    }

    private var photoConfirmBinding: Binding<Bool> {
        Binding(
            get: {
                if case .confirm = photoMealController.phase { return true }
                return false
            },
            set: { isPresented in
                if !isPresented {
                    photoMealController.cancel()
                }
            }
        )
    }

    private var photoErrorBinding: Binding<Bool> {
        Binding(
            get: {
                if case .failed = photoMealController.phase { return true }
                return false
            },
            set: { isPresented in
                if !isPresented {
                    photoMealController.dismissError()
                }
            }
        )
    }

    private var loadingCard: some View {
        HelmSkeletonCard(rowCount: 4)
    }
}

#Preview("Nutrition instrument") {
    NutritionView()
        .helmTheme()
        .environment(\.helmSkin, .instrument)
}

#Preview("Nutrition data sheet") {
    NutritionView()
        .helmTheme()
        .environment(\.helmSkin, .dataSheet)
}

#Preview("Nutrition accessibility") {
    NutritionView()
        .helmTheme()
        .dynamicTypeSize(.accessibility5)
}
