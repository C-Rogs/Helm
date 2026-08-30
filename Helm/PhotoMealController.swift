import Core
import DesignSystem
import HealthKitIngest
import Observation
import PhotosUI
import SwiftUI
import UIKit

@MainActor
@Observable
final class PhotoMealController {
    enum Phase {
        case idle
        case estimating
        case confirm(MealEstimate, previewImage: UIImage?)
        case saving
        case failed(String)
    }

    var phase: Phase = .idle
    var pickerItem: PhotosPickerItem?
    var showsCamera = false
    var preferredBucket: MealBucket = .snacks
    var userNotes = ""
    var loggingHelmDay: HelmDay?
    var todayHelmDay: HelmDay?

    private var pendingImageJPEG: Data?
    private var pendingPreview: UIImage?
    private var pendingPortionAssist: MealPortionAssistContext?
    private var estimateTask: Task<Void, Never>?
    var estimateCompletedSteps: [String] = []
    var estimateCurrentStep = "Reading photo…"

    var estimatingPreviewImage: UIImage? {
        pendingPreview
    }

    var usesLidarPortionAssist: Bool {
        pendingPortionAssist != nil
    }

    var isEstimating: Bool {
        if case .estimating = phase { return true }
        return false
    }

    var isBusy: Bool {
        switch phase {
        case .estimating, .saving:
            true
        default:
            false
        }
    }

    var busyMessage: String {
        if case .saving = phase {
            return "Saving to Health…"
        }
        return "Estimating macros…"
    }

    private var service: PhotoMealService? {
        NutritionBootstrap.photoMealService
    }

    var isAvailable: Bool {
        service != nil
    }

    func handlePickerItemChange() async {
        guard pickerItem != nil else { return }
        startEstimateTask { [self] in
            guard let pickerItem else { return }
            phase = .estimating
            defer { self.pickerItem = nil }

            guard let data = try? await pickerItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = MealPhotoJPEGPreparer.prepare(from: image)
            else {
                failUnlessCancelled("Could not read that photo.")
                return
            }

            pendingPreview = image
            await runEstimate(imageJPEGData: jpeg, preview: image)
        }
        await estimateTask?.value
    }

    func handleCameraImage(_ image: UIImage, portionAssist: MealPortionAssistContext? = nil) async {
        startEstimateTask { [self] in
            guard let jpeg = MealPhotoJPEGPreparer.prepare(from: image) else {
                failUnlessCancelled("Could not read that photo.")
                return
            }
            pendingPortionAssist = portionAssist
            await runEstimate(imageJPEGData: jpeg, preview: image)
        }
        await estimateTask?.value
    }

    func reestimateFromConfirm() async {
        guard let pendingImageJPEG else { return }
        startEstimateTask { [self] in
            await runEstimate(imageJPEGData: pendingImageJPEG, preview: pendingPreview)
        }
        await estimateTask?.value
    }

    func confirm(estimate: MealEstimate, name: String, bucket: MealBucket) async {
        let helmDay = loggingHelmDay ?? todayHelmDay ?? HelmDay.day(for: Date(), calendar: .current)
        let today = todayHelmDay ?? helmDay
        let loggedAt = MealLogInstant.loggedAt(for: helmDay, bucket: bucket, today: today)

        phase = .saving
        do {
            _ = try await HelmActionRuntime.perform(
                .meal(.logPhoto(
                    estimate: estimate,
                    name: name,
                    bucket: bucket,
                    loggedAt: loggedAt,
                    helmDay: helmDay,
                    mealID: UUID().uuidString
                )),
                after: .coach
            )
            pendingImageJPEG = nil
            pendingPreview = nil
            pendingPortionAssist = nil
            phase = .idle
        } catch {
            phase = .failed(PhotoMealService.userMessage(for: error))
        }
    }

    func cancel() {
        estimateTask?.cancel()
        estimateTask = nil
        pendingImageJPEG = nil
        pendingPreview = nil
        pendingPortionAssist = nil
        resetEstimateProgress()
        phase = .idle
    }

    func dismissError() {
        if case .failed = phase {
            pickerItem = nil
            phase = .idle
        }
    }

    func prepareForNewPhotoSelection() {
        pickerItem = nil
    }

    private func resetEstimateProgress() {
        estimateCompletedSteps = []
        estimateCurrentStep = pendingPortionAssist == nil
            ? "Reading photo…"
            : "Reading photo with LiDAR depth…"
    }

    private func reportEstimateProgress(_ step: String) {
        guard estimateCurrentStep != step else { return }
        if !estimateCurrentStep.isEmpty {
            estimateCompletedSteps.append(estimateCurrentStep)
        }
        estimateCurrentStep = step
    }

    private func startEstimateTask(_ operation: @escaping @MainActor () async -> Void) {
        estimateTask?.cancel()
        estimateTask = Task {
            await operation()
        }
    }

    private func runEstimate(imageJPEGData: Data, preview: UIImage?) async {
        guard !Task.isCancelled else {
            cancel()
            return
        }

        guard let service else {
            failUnlessCancelled("Add a Gemini or OpenRouter API key in Settings to log meals from photos.")
            return
        }

        pendingImageJPEG = imageJPEGData
        pendingPreview = preview
        resetEstimateProgress()
        phase = .estimating
        let notes = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let userNotesPayload = notes.isEmpty ? nil : notes
        do {
            let estimate = try await service.estimate(
                from: imageJPEGData,
                userNotes: userNotesPayload,
                portionAssist: pendingPortionAssist,
                progress: { [weak self] step in
                    Task { @MainActor in
                        self?.reportEstimateProgress(step)
                    }
                }
            )
            guard !Task.isCancelled else {
                cancel()
                return
            }
            phase = .confirm(estimate, previewImage: preview)
        } catch {
            guard !Task.isCancelled else {
                cancel()
                return
            }
            if error is CancellationError {
                cancel()
                return
            }
            phase = .failed(PhotoMealService.userMessage(for: error))
        }
    }

    private func failUnlessCancelled(_ message: String) {
        guard !Task.isCancelled else {
            cancel()
            return
        }
        phase = .failed(message)
    }
}

struct CameraImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker

        init(parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }
    }
}
