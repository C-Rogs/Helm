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
        pendingImportService: NutritionBootstrap.pendingFoodImportService,
        portionPreferenceLoader: { ref in
            try PersistenceBootstrap.persistenceStore.foodLog.fetchPortionPreference(ref: ref)
        },
        onLogged: { helmDay in
            NutritionBootstrap.refreshNutrition(for: helmDay)
        }
    )
    @State private var mealsStore = NutritionDayMealsStore()
    @State private var mealActionsController = NutritionMealActionsController(
        mealRepeatService: NutritionBootstrap.mealRepeatService,
        onChanged: {
            NutritionBootstrap.refreshNutrition(for: NutritionBootstrap.lastViewedHelmDay)
        }
    )
    @State private var mealEditController = MealEditController(
        manualMealService: NutritionBootstrap.manualMealService,
        onChanged: {
            NutritionBootstrap.refreshNutrition(for: NutritionBootstrap.lastViewedHelmDay)
        }
    )
    @State private var foodLogTipStore = FoodLogTipStore.shared
    @State private var isRefreshing = false
    @State private var isDayCompleteSaving = false
    @State private var showsPhotoOptions = false
    @State private var showsTemplates = false
    @State private var selectedHelmDay: HelmDay?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        navigationStack
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { refreshToolbar }
            .task { await refreshTargets() }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    await manualFoodLogController.refreshConnectivity()
                }
            }
            .onChange(of: prescriptionService.state) { _, newState in
                Task {
                    await refreshSelectedDay(prescriptionSummary: newState.summary)
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
            .onChange(of: photoMealController.pickerItem) { _, newValue in
                if newValue != nil {
                    showsPhotoOptions = false
                }
                Task { await photoMealController.handlePickerItemChange() }
            }
            .modifier(NutritionLoggingSheets(
                photoMealController: photoMealController,
                manualFoodLogController: manualFoodLogController,
                mealActionsController: mealActionsController,
                mealEditController: mealEditController,
                showsPhotoOptions: $showsPhotoOptions,
                showsTemplates: $showsTemplates,
                currentHelmDay: selectedHelmDay,
                onMealsChanged: {
                    reloadMeals(from: nutritionService.state)
                }
            ))
    }

    private var navigationStack: some View {
        NavigationStack {
            ScrollView {
                HelmScreenStack {
                    switch nutritionService.state {
                    case .loading:
                        loadingCard
                    case let .ready(snapshot):
                        if let selectedHelmDay, let todayHelmDay {
                            NutritionDiaryHeader(
                                selectedDay: selectedHelmDay,
                                today: todayHelmDay,
                                onSelectDay: { day in
                                    Task { await selectDay(day) }
                                }
                            )
                        }

                        NutritionDaySummaryCard(
                            snapshot: snapshot,
                            showTrend: false,
                            explainMetric: ExplainableMetricMappers.nutrition(
                                snapshot,
                                coachAvailable: chatController.isCoachAvailable
                            ),
                            onAskCoach: chatController.requestCoachHandoff(prompt:)
                        )

                        if foodLogTipStore.isVisible {
                            foodLogTipCard
                        }

                        mealBucketsSection(snapshot: snapshot)

                        NutritionDayCompleteSection(
                            loggingComplete: snapshot.loggingComplete,
                            isSaving: isDayCompleteSaving,
                            onMarkComplete: {
                                Task { await markDayComplete() }
                            },
                            onReopen: {
                                Task { await reopenDay() }
                            }
                        )
                    }
                }
                .helmScreenPadding()
            }
            .helmScreenBackground()
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
                        guard let day = selectedHelmDay else { return }
                        await mealActionsController.copyYesterdayToToday(today: day)
                        await refreshSelectedDay()
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
        let today = HelmDay.day(for: Date(), calendar: .current)
        if selectedHelmDay == nil {
            selectedHelmDay = today
        }
        syncLoggingContext()
        await refreshSelectedDay()
    }

    @MainActor
    private func refreshSelectedDay(
        prescriptionSummary: PrescribedSessionSummary? = PlanBootstrap.prescriptionService.state.summary
    ) async {
        guard let day = selectedHelmDay else { return }
        NutritionBootstrap.lastViewedHelmDay = day
        await nutritionService.refresh(for: day, prescriptionSummary: prescriptionSummary)
        reloadMeals(from: nutritionService.state)
    }

    @MainActor
    private func selectDay(_ day: HelmDay) async {
        selectedHelmDay = day
        syncLoggingContext()
        await refreshSelectedDay()
    }

    private var todayHelmDay: HelmDay? {
        HelmDay.day(for: Date(), calendar: .current)
    }

    private func syncLoggingContext() {
        let today = todayHelmDay ?? HelmDay.day(for: Date(), calendar: .current)
        manualFoodLogController.todayHelmDay = today
        manualFoodLogController.loggingHelmDay = selectedHelmDay ?? today
        photoMealController.todayHelmDay = today
        photoMealController.loggingHelmDay = selectedHelmDay ?? today
    }

    @MainActor
    private func markDayComplete() async {
        guard let day = selectedHelmDay else { return }
        isDayCompleteSaving = true
        defer { isDayCompleteSaving = false }
        do {
            try PersistenceBootstrap.persistenceStore.nutritionLogStatus.markComplete(helmDay: day)
            HapticEngine.shared.play(.mealConfirmed)
            await refreshSelectedDay()
        } catch {
            // Non-fatal; refresh will show current state.
        }
    }

    @MainActor
    private func reopenDay() async {
        guard let day = selectedHelmDay else { return }
        isDayCompleteSaving = true
        defer { isDayCompleteSaving = false }
        do {
            try PersistenceBootstrap.persistenceStore.nutritionLogStatus.clearComplete(helmDay: day)
            await refreshSelectedDay()
        } catch {
            // Non-fatal.
        }
    }

    private func reloadMeals(from state: NutritionDashboardState) {
        guard case let .ready(snapshot) = state else { return }
        if selectedHelmDay == nil {
            selectedHelmDay = snapshot.helmDay
            syncLoggingContext()
        }
        let day = selectedHelmDay ?? snapshot.helmDay
        mealsStore.reload(for: day)
    }

    @ViewBuilder
    private func mealBucketsSection(snapshot: NutritionDaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HelmSectionEyebrow("MEALS", showsArcMark: true)

            ForEach(MealBucket.allCases, id: \.self) { bucket in
                NutritionMealBucketSection(
                    bucket: bucket,
                    meals: mealsStore.mealsByBucket[bucket] ?? [],
                    isPhotoAvailable: photoMealController.isAvailable,
                    onCopyToToday: {
                        Task {
                            guard let day = selectedHelmDay else { return }
                            await mealActionsController.copyBucketToToday(bucket: bucket, today: day)
                            await refreshSelectedDay()
                        }
                    },
                    onSaveTemplate: {
                        mealActionsController.beginSaveTemplate(for: bucket)
                    },
                    onMealTap: { display in
                        mealEditController.beginEdit(display)
                    },
                    onAddFood: { action in
                        handleBucketAddFood(action, bucket: bucket)
                    }
                )
            }
        }
    }

    private func handleBucketAddFood(_ action: BucketFoodLogAction, bucket: MealBucket) {
        syncLoggingContext()
        manualFoodLogController.preferredBucket = bucket
        photoMealController.preferredBucket = bucket
        switch action {
        case .search:
            manualFoodLogController.start(.search, bucket: bucket)
        case .barcode:
            manualFoodLogController.start(.barcode, bucket: bucket)
        case .quickAdd:
            manualFoodLogController.start(.quickAdd, bucket: bucket)
        case .alcohol:
            manualFoodLogController.start(.alcohol, bucket: bucket)
        case .photo:
            photoMealController.preferredBucket = bucket
            showsPhotoOptions = true
        }
    }

    private var foodLogTipCard: some View {
        Card {
            HStack(alignment: .top, spacing: HelmSpacing.sm) {
                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    HelmSectionEyebrow("LOG FOOD", showsArcMark: true)
                    Text("Tap + on a meal panel to search, scan, photo, or quick-add. Food logs to that meal by default.")
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
    let mealEditController: MealEditController
    @Binding var showsPhotoOptions: Bool
    @Binding var showsTemplates: Bool
    let currentHelmDay: HelmDay?
    let onMealsChanged: () -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: photoEstimatingBinding) {
                PhotoMealEstimatingView(
                    previewImage: photoMealController.estimatingPreviewImage,
                    completedSteps: photoMealController.estimateCompletedSteps,
                    currentStep: photoMealController.estimateCurrentStep,
                    usesLidarAssist: photoMealController.usesLidarPortionAssist,
                    onCancel: { photoMealController.cancel() }
                )
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
            .sheet(isPresented: Binding(
                get: { photoMealController.showsCamera },
                set: { photoMealController.showsCamera = $0 }
            )) {
                if MealDepthPortionAssist.isAvailable {
                    MealDepthCameraView { image, portionAssist in
                        Task { await photoMealController.handleCameraImage(image, portionAssist: portionAssist) }
                    }
                    .ignoresSafeArea()
                } else {
                    CameraImagePicker { image in
                        Task { await photoMealController.handleCameraImage(image) }
                    }
                    .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showsPhotoOptions) {
                PhotoLogOptionsSheet(
                    pickerItem: Binding(
                        get: { photoMealController.pickerItem },
                        set: { photoMealController.pickerItem = $0 }
                    ),
                    userNotes: Binding(
                        get: { photoMealController.userNotes },
                        set: { photoMealController.userNotes = $0 }
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
            .sheet(item: mealEditBinding) { display in
                MealEditSheet(
                    display: display,
                    isSaving: mealEditController.isSaving,
                    onSave: { name, lineItems, quickAddMacros, bucket in
                        Task {
                            await mealEditController.save(
                                name: name,
                                lineItems: lineItems,
                                quickAddMacros: quickAddMacros,
                                bucket: bucket
                            )
                            onMealsChanged()
                        }
                    },
                    onDelete: {
                        Task {
                            await mealEditController.delete()
                            onMealsChanged()
                        }
                    },
                    onCancel: {
                        mealEditController.cancel()
                    }
                )
            }
            .alert(
                "Edit entry",
                isPresented: mealEditErrorBinding,
                actions: {
                    Button("OK", role: .cancel) {
                        mealEditController.dismissError()
                    }
                },
                message: {
                    if let errorMessage = mealEditController.errorMessage {
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

    private var mealEditBinding: Binding<LoggedMealDisplay?> {
        Binding(
            get: { mealEditController.selectedMeal },
            set: { isPresented in
                if isPresented == nil {
                    mealEditController.cancel()
                }
            }
        )
    }

    private var mealEditErrorBinding: Binding<Bool> {
        Binding(
            get: { mealEditController.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    mealEditController.dismissError()
                }
            }
        )
    }

    private var photoEstimatingBinding: Binding<Bool> {
        Binding(
            get: { photoMealController.isEstimating },
            set: { isPresented in
                if !isPresented, photoMealController.isEstimating {
                    photoMealController.cancel()
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
