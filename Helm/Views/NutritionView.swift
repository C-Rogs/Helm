import Core
import DesignSystem
import HealthKitIngest
import PhotosUI
import SwiftUI

struct NutritionView: View {
    private var nutritionService: NutritionService { NutritionBootstrap.nutritionService }
    private var prescriptionService: PrescriptionService { PlanBootstrap.prescriptionService }
    @Bindable private var chatController = ChatBootstrap.controller
    @State private var photoMealController = PhotoMealController()
    @State private var manualFoodLogController = ManualFoodLogController(
        foodResolver: NutritionBootstrap.foodResolver,
        manualMealService: NutritionBootstrap.manualMealService,
        portionPreferenceLoader: { ref in
            try PersistenceBootstrap.persistenceStore.foodLog.fetchPortionPreference(ref: ref)
        },
        onLogged: {
            NutritionBootstrap.refreshNutrition()
        }
    )
    @State private var mealsStore = NutritionDayMealsStore()
    @State private var mealActionsController = NutritionMealActionsController(
        mealRepeatService: NutritionBootstrap.mealRepeatService,
        onChanged: {
            NutritionBootstrap.refreshNutrition()
        }
    )
    @State private var foodLogTipStore = FoodLogTipStore.shared
    @State private var isRefreshing = false
    @State private var isFABExpanded = false
    @State private var showsPhotoOptions = false
    @State private var showsTemplates = false
    @State private var currentHelmDay: HelmDay?

    var body: some View {
        navigationStack
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { refreshToolbar }
            .task { await refreshTargets() }
            .onChange(of: prescriptionService.state) { _, newState in
                Task {
                    await nutritionService.refresh(prescriptionSummary: newState.summary)
                }
            }
            .onChange(of: nutritionService.state) { _, newState in
                reloadMeals(from: newState)
            }
            .onChange(of: manualFoodLogController.phase) { _, newPhase in
                if case .idle = newPhase {
                    reloadMeals(from: nutritionService.state)
                }
            }
            .onChange(of: photoMealController.pickerItem) { _, _ in
                Task { await photoMealController.handlePickerItemChange() }
            }
            .modifier(NutritionLoggingSheets(
                photoMealController: photoMealController,
                manualFoodLogController: manualFoodLogController,
                mealActionsController: mealActionsController,
                showsPhotoOptions: $showsPhotoOptions,
                showsTemplates: $showsTemplates,
                currentHelmDay: currentHelmDay,
                onMealsChanged: {
                    reloadMeals(from: nutritionService.state)
                }
            ))
    }

    private var navigationStack: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    HelmScreenStack {
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

                            if foodLogTipStore.isVisible {
                                foodLogTipCard
                            }

                            mealBucketsSection
                        }
                    }
                    .helmScreenPadding()
                    .padding(.bottom, HelmSpacing.xl * 2)
                }
                .helmScreenBackground()

                NutritionFoodLogFAB(
                    isExpanded: $isFABExpanded,
                    isPhotoAvailable: photoMealController.isAvailable,
                    onSearch: { manualFoodLogController.startSearch() },
                    onBarcode: { manualFoodLogController.startBarcode() },
                    onPhoto: { showsPhotoOptions = true },
                    onQuickAdd: { manualFoodLogController.startQuickAdd() },
                    onAlcohol: { manualFoodLogController.startAlcohol() }
                )
                .padding(HelmSpacing.lg)
            }
        }
    }

    @ToolbarContentBuilder
    private var refreshToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Meal templates") {
                    mealActionsController.reloadTemplates()
                    showsTemplates = true
                }
                Button("Copy yesterday's meals") {
                    Task {
                        guard let today = currentHelmDay else { return }
                        await mealActionsController.copyYesterdayToToday(today: today)
                        reloadMeals(from: nutritionService.state)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Nutrition actions")
        }
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

    @MainActor
    private func refreshTargets() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await nutritionService.refresh(
            prescriptionSummary: prescriptionService.state.summary
        )
        reloadMeals(from: nutritionService.state)
    }

    private func reloadMeals(from state: NutritionDashboardState) {
        guard case let .ready(snapshot) = state else { return }
        currentHelmDay = snapshot.helmDay
        mealsStore.reload(for: snapshot.helmDay)
    }

    @ViewBuilder
    private var mealBucketsSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HelmSectionEyebrow("MEALS", showsArcMark: true)

            ForEach(MealBucket.allCases, id: \.self) { bucket in
                NutritionMealBucketSection(
                    bucket: bucket,
                    meals: mealsStore.mealsByBucket[bucket] ?? [],
                    onCopyToToday: {
                        Task {
                            guard let today = currentHelmDay else { return }
                            await mealActionsController.copyBucketToToday(bucket: bucket, today: today)
                            reloadMeals(from: nutritionService.state)
                        }
                    },
                    onSaveTemplate: {
                        mealActionsController.beginSaveTemplate(for: bucket)
                    }
                )
            }
        }
    }

    private var foodLogTipCard: some View {
        Card {
            HStack(alignment: .top, spacing: HelmSpacing.sm) {
                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    HelmSectionEyebrow("LOG FOOD", showsArcMark: true)
                    Text("Tap + to search, scan, photo, or quick-add. Pick a meal bucket when you save.")
                        .helmType(.body, color: HelmColor.fgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    foodLogTipStore.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HelmColor.fgMuted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.helmPressable)
                .accessibilityLabel("Dismiss tip")
            }
        }
    }

    private var loadingCard: some View {
        HelmLoadingState(rowCount: 3)
    }
}

private struct NutritionLoggingSheets: ViewModifier {
    let photoMealController: PhotoMealController
    let manualFoodLogController: ManualFoodLogController
    let mealActionsController: NutritionMealActionsController
    @Binding var showsPhotoOptions: Bool
    @Binding var showsTemplates: Bool
    let currentHelmDay: HelmDay?
    let onMealsChanged: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: photoConfirmBinding) {
                if case let .confirm(estimate, previewImage) = photoMealController.phase {
                    PhotoMealConfirmSheet(
                        controller: photoMealController,
                        initialEstimate: estimate,
                        previewImage: previewImage
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { photoMealController.showsCamera },
                set: { photoMealController.showsCamera = $0 }
            )) {
                CameraImagePicker { image in
                    Task { await photoMealController.handleCameraImage(image) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showsPhotoOptions) {
                PhotoLogOptionsSheet(
                    pickerItem: Binding(
                        get: { photoMealController.pickerItem },
                        set: { photoMealController.pickerItem = $0 }
                    ),
                    onCamera: { photoMealController.showsCamera = true },
                    onCancel: { showsPhotoOptions = false }
                )
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
            .sheet(item: manualFoodFlowBinding) { mode in
                AddFoodFlowView(controller: manualFoodLogController, entryMode: mode)
            }
            .alert(
                "Food logging",
                isPresented: manualFoodErrorBinding,
                actions: {
                    Button("OK", role: .cancel) {
                        manualFoodLogController.dismissError()
                    }
                },
                message: {
                    if case let .failed(message) = manualFoodLogController.phase {
                        Text(message)
                    }
                }
            )
            .sheet(isPresented: saveTemplateBinding) {
                if let bucket = mealActionsController.saveTemplateBucket, let helmDay = currentHelmDay {
                    SaveMealTemplateSheet(
                        bucket: bucket,
                        onSave: { name in
                            mealActionsController.saveTemplate(name: name, bucket: bucket, helmDay: helmDay)
                        },
                        onCancel: {
                            mealActionsController.cancelSaveTemplate()
                        }
                    )
                }
            }
            .sheet(isPresented: $showsTemplates) {
                MealTemplatesSheet(
                    templates: mealActionsController.templates,
                    onLog: { template in
                        showsTemplates = false
                        mealActionsController.beginLogTemplate(template)
                    },
                    onDelete: { template in
                        mealActionsController.deleteTemplate(template)
                    },
                    onDismiss: {
                        showsTemplates = false
                    }
                )
            }
            .sheet(item: logTemplateBinding) { template in
                LogMealTemplateConfirmSheet(
                    template: template,
                    isSaving: mealActionsController.isSaving,
                    onConfirm: {
                        Task {
                            await mealActionsController.confirmLogTemplate(template)
                            onMealsChanged()
                        }
                    },
                    onCancel: {
                        mealActionsController.cancelPendingAction()
                    }
                )
            }
            .alert(
                "Meal actions",
                isPresented: mealActionsErrorBinding,
                actions: {
                    Button("OK", role: .cancel) {
                        mealActionsController.dismissError()
                    }
                },
                message: {
                    if let errorMessage = mealActionsController.errorMessage {
                        Text(errorMessage)
                    }
                }
            )
    }

    private var saveTemplateBinding: Binding<Bool> {
        Binding(
            get: { mealActionsController.saveTemplateBucket != nil },
            set: { isPresented in
                if !isPresented {
                    mealActionsController.cancelSaveTemplate()
                }
            }
        )
    }

    private var logTemplateBinding: Binding<MealTemplate?> {
        Binding(
            get: {
                if case let .logTemplate(template) = mealActionsController.pendingAction {
                    return template
                }
                return nil
            },
            set: { isPresented in
                if isPresented == nil {
                    mealActionsController.cancelPendingAction()
                }
            }
        )
    }

    private var mealActionsErrorBinding: Binding<Bool> {
        Binding(
            get: { mealActionsController.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    mealActionsController.dismissError()
                }
            }
        )
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

    private var manualFoodFlowBinding: Binding<AddFoodEntryMode?> {
        Binding(
            get: {
                if case let .flow(mode) = manualFoodLogController.phase {
                    return mode
                }
                return nil
            },
            set: { isPresented in
                if isPresented == nil {
                    manualFoodLogController.cancel()
                }
            }
        )
    }

    private var manualFoodErrorBinding: Binding<Bool> {
        Binding(
            get: {
                if case .failed = manualFoodLogController.phase { return true }
                return false
            },
            set: { isPresented in
                if !isPresented {
                    manualFoodLogController.dismissError()
                }
            }
        )
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

#Preview("Nutrition loading") {
    ScrollView {
        HelmScreenStack {
            HelmLoadingState(rowCount: 3)
        }
        .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Nutrition empty buckets") {
    ScrollView {
        HelmScreenStack {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HelmSectionEyebrow("MEALS")
                ForEach(MealBucket.allCases, id: \.self) { bucket in
                    NutritionMealBucketSection(bucket: bucket, meals: [])
                }
            }
        }
        .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Nutrition error") {
    ScrollView {
        HelmErrorState(
            title: "Targets unavailable",
            message: "Could not load nutrition targets.",
            onRetry: {}
        )
        .helmScreenPadding()
    }
    .helmTheme()
}
