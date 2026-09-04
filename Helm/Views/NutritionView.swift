import Core
import DesignSystem
import HealthKitIngest
import NutritionKit
import PhotosUI
import SwiftUI
import UIKit

struct NutritionView: View {
    private var nutritionService: NutritionService { NutritionBootstrap.nutritionService }
    private var prescriptionService: PrescriptionService { PlanBootstrap.prescriptionService }
    @Bindable private var chatController = ChatBootstrap.controller
    @Bindable private var tabRouter = AppTabRouter.shared
    @State private var photoMealController = PhotoMealController()
    @State private var manualFoodLogController = ManualFoodLogController(
        foodResolver: NutritionBootstrap.foodResolver,
        actionExecutor: HelmActionRuntime.executor,
        pendingImportService: NutritionBootstrap.pendingFoodImportService,
        portionPreferenceLoader: { ref in
            try PersistenceBootstrap.persistenceStore.foodLog.fetchPortionPreference(ref: ref)
        },
        onLogged: { helmDay in
            NutritionBootstrap.refreshNutrition(for: helmDay)
        }
    )
    @State private var mealsStore = NutritionDayMealsStore()
    @State private var usualMealStore = UsualMealStore()
    @State private var mealActionsController = NutritionMealActionsController(
        mealRepeatService: NutritionBootstrap.mealRepeatService,
        actionExecutor: HelmActionRuntime.executor
    )
    @State private var mealEditController = MealEditController(
        actionExecutor: HelmActionRuntime.executor
    )
    @State private var foodLogTipStore = FoodLogTipStore.shared
    @State private var patternLoggingTipStore = PatternLoggingTipStore.shared
    @State private var isRefreshing = false
    @State private var isDayCompleteSaving = false
    @State private var showsPhotoOptions = false
    @State private var showsTemplates = false
    @State private var selectedHelmDay: HelmDay?
    @State private var describeBucket: MealBucket?
    @State private var describeText = ""
    // Gates confirm-sheet presentation and error alerts to turns started from
    // this tab, so an unrelated chat conversation cannot surface here.
    @State private var isDescribeFlowActive = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            diaryScroll
                .helmScreenBackground()
                .refreshable {
                    await refreshTargets()
                }
                .navigationTitle("Nutrition")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { nutritionToolbar }
        }
        .task {
            await AppTabRouter.shared.preferChromeOverContentLoad()
            guard !Task.isCancelled else { return }
            await refreshTargets()
        }
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
        .onChange(of: tabRouter.pendingNutritionFocus) { _, focus in
            guard let focus else { return }
            Task { await applyNutritionFocus(focus) }
        }
        .onChange(of: manualFoodLogController.phase) { _, newPhase in
            if case .idle = newPhase {
                reloadMeals(from: nutritionService.state)
            }
        }
        .onChange(of: photoMealController.pickerItem) { _, newValue in
            // Dismiss options first; estimate starts in sheet onDismiss so fullScreenCover
            // is not cancelled by the options sheet teardown race.
            if newValue != nil {
                showsPhotoOptions = false
            }
        }
        .modifier(NutritionLoggingSheets(
            photoMealController: photoMealController,
            manualFoodLogController: manualFoodLogController,
            mealActionsController: mealActionsController,
            mealEditController: mealEditController,
            showsPhotoOptions: $showsPhotoOptions,
            showsTemplates: $showsTemplates,
            currentHelmDay: selectedHelmDay,
            todayHelmDay: todayHelmDay,
            onMealsChanged: {
                reloadMeals(from: nutritionService.state)
            }
        ))
        .sheet(isPresented: Binding(
            get: { describeBucket != nil },
            set: { if !$0 { describeBucket = nil } }
        )) {
            if let bucket = describeBucket {
                DescribeFoodSheet(
                    bucket: bucket,
                    text: $describeText,
                    onSubmit: { text in
                        describeBucket = nil
                        sendDescribeFood(text, bucket: bucket)
                    },
                    onUseSearch: {
                        describeBucket = nil
                        manualFoodLogController.start(.search, bucket: bucket)
                    }
                )
                .presentationDetents([.height(260)])
            }
        }
        .sheet(isPresented: Binding(
            get: { isDescribeFlowActive && chatController.pendingFoodMealConfirm != nil },
            set: { if !$0 { chatController.dismissFoodMealConfirm() } }
        )) {
            if let state = chatController.pendingFoodMealConfirm {
                CoachFoodMealConfirmSheet(
                    state: state,
                    isSaving: chatController.isApplyingChatAction,
                    errorMessage: chatController.lastTurnError,
                    onCancel: {
                        chatController.dismissFoodMealConfirm()
                        isDescribeFlowActive = false
                    },
                    onConfirm: { estimate, name, bucket in
                        chatController.confirmFoodMeal(estimate: estimate, name: name, bucket: bucket)
                    }
                )
            }
        }
        .onChange(of: chatController.pendingFoodMealConfirm == nil) { _, isCleared in
            guard isCleared, isDescribeFlowActive, !chatController.isStreaming,
                  !chatController.isPreparingFoodMealConfirm else { return }
            isDescribeFlowActive = false
            Task { await refreshSelectedDay() }
        }
        .alert(
            "Couldn't estimate that meal",
            isPresented: Binding(
                get: {
                    isDescribeFlowActive
                        && chatController.pendingFoodMealConfirm == nil
                        && !chatController.isStreaming
                        && !chatController.isPreparingFoodMealConfirm
                        && chatController.lastTurnError != nil
                },
                set: { if !$0 { isDescribeFlowActive = false } }
            )
        ) {
            Button("Use Search") {
                isDescribeFlowActive = false
                manualFoodLogController.start(.search, bucket: manualFoodLogController.preferredBucket)
            }
            Button("OK", role: .cancel) {
                isDescribeFlowActive = false
            }
        } message: {
            Text(chatController.lastTurnError ?? "The coach needs a network connection to estimate meals. Search works offline.")
        }
        .overlay(alignment: .bottom) {
            if isDescribeFlowActive,
               chatController.isStreaming || chatController.isPreparingFoodMealConfirm {
                describeProgressBanner
            }
        }
        .animation(HelmMotion.standardAnimation, value: chatController.isStreaming)
        .animation(HelmMotion.standardAnimation, value: chatController.isPreparingFoodMealConfirm)
    }

    @ViewBuilder
    private var diaryScroll: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                HelmScreenStack {
                    switch nutritionService.state {
                    case .loading:
                        loadingCard
                    case let .ready(snapshot):
                        diaryReadyContent(snapshot)
                    }
                }
                .helmScreenPadding()
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .contentShape(Rectangle())
            .background(NutritionHorizontalScrollLock())
        }
    }

    @ViewBuilder
    private func diaryReadyContent(_ snapshot: NutritionDaySnapshot) -> some View {
        if let selectedHelmDay, let todayHelmDay {
            NutritionDiaryHeader(
                selectedDay: selectedHelmDay,
                today: todayHelmDay,
                budget: snapshot.weeklyBudget,
                onSelectDay: { day in
                    Task { await selectDay(day) }
                },
                onSetDemand: { day, demand in
                    Task { await setDayDemand(demand, for: day) }
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

        if patternLoggingTipStore.activeTip != nil {
            patternLoggingTipCard
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

    private func sendDescribeFood(_ text: String, bucket: MealBucket) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var transcript = "\(trimmed) (log to \(bucket.displayName.lowercased()))"
        if let day = selectedHelmDay, let today = todayHelmDay, day != today {
            transcript += " for \(day.formatted)"
        }
        isDescribeFlowActive = true
        chatController.sendFoodDictation(transcript)
    }

    private var describeProgressBanner: some View {
        CoachAIProgressCard(
            eyebrow: "COACH",
            title: chatController.chatProgressTitle ?? "Estimating meal",
            completedSteps: chatController.chatProgressCompletedSteps,
            currentStep: chatController.chatProgressStep ?? "Estimating your meal…",
            isImpactful: true
        )
        .helmScreenPadding()
        .padding(.bottom, HelmSpacing.lg)
        .transition(.opacity)
    }

    @ToolbarContentBuilder
    private var nutritionToolbar: some ToolbarContent {
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
            .accessibilityLabel("Refresh")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Saved meals") {
                    openTemplates()
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
    }

    private func openTemplates() {
        mealActionsController.reloadTemplates()
        showsTemplates = true
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
    private func setDayDemand(_ demand: NutritionDayDemand?, for day: HelmDay) async {
        let service = NutritionDayDemandService(persistence: PersistenceBootstrap.persistenceStore)
        do {
            if let demand {
                try service.setExplicitOverride(demand, for: day)
                if demand == .office {
                    patternLoggingTipStore.noteOfficeTagged()
                }
            } else {
                try service.clearExplicitOverride(for: day)
            }
            HapticEngine.shared.play(.mealConfirmed)
            await refreshSelectedDay()
        } catch {
            // Non-fatal; next refresh shows current state.
        }
    }

    @MainActor
    private func selectDay(_ day: HelmDay) async {
        selectedHelmDay = day
        syncLoggingContext()
        await refreshSelectedDay()
    }

    @MainActor
    private func applyNutritionFocus(_ focus: NutritionNavigationFocus) async {
        AppTabRouter.shared.pendingNutritionFocus = nil
        await selectDay(focus.helmDay)
        mealsStore.reload(for: focus.helmDay)
        usualMealStore.reload(for: focus.helmDay)
        if focus.startSearch, let bucket = focus.bucket {
            handleBucketAddFood(.search, bucket: bucket)
            return
        }
        guard let mealID = focus.mealID else { return }
        let displays = MealBucket.allCases.flatMap { mealsStore.mealsByBucket[$0] ?? [] }
        if let display = displays.first(where: { $0.id == mealID }) {
            mealEditController.beginEdit(display)
        }
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
        usualMealStore.reload(for: day)
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
                    isDescribeAvailable: chatController.isCoachAvailable,
                    usualProposal: usualMealStore.proposal(for: bucket),
                    isLoggingUsual: usualMealStore.loggingBucket == bucket,
                    onCopyEntry: {
                        guard let day = selectedHelmDay else { return }
                        mealActionsController.beginCopyEntry(sourceDay: day, sourceBucket: bucket)
                    },
                    onSaveTemplate: {
                        mealActionsController.beginSaveTemplate(for: bucket)
                    },
                    onMealTap: { display in
                        mealEditController.beginEdit(display)
                    },
                    onAddFood: { action in
                        handleBucketAddFood(action, bucket: bucket)
                    },
                    onLogUsual: {
                        guard let day = selectedHelmDay,
                              let proposal = usualMealStore.proposal(for: bucket) else { return }
                        Task {
                            await usualMealStore.log(proposal, helmDay: day)
                            mealsStore.reload(for: day)
                        }
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
        case .describe:
            describeText = ""
            describeBucket = bucket
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
            photoMealController.prepareForNewPhotoSelection()
            showsPhotoOptions = true
        case .savedMeals:
            openTemplates()
        }
    }

    private var foodLogTipCard: some View {
        Card {
            HStack(alignment: .top, spacing: HelmSpacing.sm) {
                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    HelmSectionEyebrow("LOG FOOD", showsArcMark: true)
                    Text("Tap + on a meal to search, scan, photo, or quick-add.")
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

    private var patternLoggingTipCard: some View {
        Card {
            HStack(alignment: .top, spacing: HelmSpacing.sm) {
                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    HelmSectionEyebrow("PATTERNS", showsArcMark: true)
                    Text(patternLoggingTipStore.headline)
                        .helmType(.body, color: HelmColor.fgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    patternLoggingTipStore.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HelmColor.fgMuted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.helmPressable)
                .accessibilityLabel("Dismiss pattern tip")
            }
        }
    }

    private var loadingCard: some View {
        HelmLoadingState(rowCount: 3)
    }
}

/// Hard-locks horizontal pan/bounce on the diary ScrollView. SwiftUI has no `.never` bounce mode.
private final class NutritionScrollLockView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        lock()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        lock()
    }

    private func lock() {
        var ancestor: UIView? = superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                scroll.alwaysBounceHorizontal = false
                scroll.showsHorizontalScrollIndicator = false
                scroll.isDirectionalLockEnabled = true
                scroll.bouncesHorizontally = false
                let inset = scroll.adjustedContentInset
                let maxWidth = max(scroll.bounds.width - inset.left - inset.right, 0)
                if maxWidth > 0, scroll.contentSize.width > maxWidth + 0.5 {
                    scroll.contentSize.width = maxWidth
                }
                if abs(scroll.contentOffset.x + inset.left) > 0.5 {
                    scroll.contentOffset.x = -inset.left
                }
            }
            ancestor = current.superview
        }
    }
}

private struct NutritionHorizontalScrollLock: UIViewRepresentable {
    func makeUIView(context: Context) -> NutritionScrollLockView {
        let view = NutritionScrollLockView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: NutritionScrollLockView, context: Context) {
        uiView.setNeedsLayout()
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
    let todayHelmDay: HelmDay?
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
            .sheet(isPresented: $showsPhotoOptions, onDismiss: {
                Task { await photoMealController.handlePickerItemChange() }
            }) {
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
            .sheet(isPresented: copyEntryBinding) {
                if let context = mealActionsController.copyEntryContext,
                   let today = todayHelmDay ?? currentHelmDay {
                    CopyMealEntrySheet(
                        sourceDay: context.sourceDay,
                        sourceBucket: context.sourceBucket,
                        today: today,
                        isSaving: mealActionsController.isSaving,
                        onConfirm: { targetDay, targetBucket in
                            Task {
                                await mealActionsController.confirmCopyEntry(
                                    targetDay: targetDay,
                                    targetBucket: targetBucket
                                )
                                onMealsChanged()
                            }
                        },
                        onCancel: {
                            mealActionsController.cancelCopyEntry()
                        }
                    )
                }
            }
            .sheet(isPresented: $showsTemplates) {
                MealTemplatesSheet(
                    templates: mealActionsController.templates,
                    onLog: { template in
                        showsTemplates = false
                        Task {
                            guard let helmDay = currentHelmDay else { return }
                            let today = todayHelmDay ?? helmDay
                            await mealActionsController.confirmLogTemplate(
                                template,
                                helmDay: helmDay,
                                today: today
                            )
                            onMealsChanged()
                        }
                    },
                    onDelete: { template in
                        mealActionsController.deleteTemplate(template)
                    },
                    onDismiss: {
                        showsTemplates = false
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

    private var copyEntryBinding: Binding<Bool> {
        Binding(
            get: { mealActionsController.copyEntryContext != nil },
            set: { isPresented in
                if !isPresented {
                    mealActionsController.cancelCopyEntry()
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
