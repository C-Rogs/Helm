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

    private let service: PhotoMealService?

    init(service: PhotoMealService? = NutritionBootstrap.photoMealService) {
        self.service = service
    }

    var isAvailable: Bool {
        service != nil
    }

    func handlePickerItemChange() async {
        guard let pickerItem else { return }
        defer { self.pickerItem = nil }

        guard let data = try? await pickerItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.82)
        else {
            phase = .failed("Could not read that photo.")
            return
        }

        await estimate(imageJPEGData: jpeg, preview: image)
    }

    func handleCameraImage(_ image: UIImage) async {
        guard let jpeg = image.jpegData(compressionQuality: 0.82) else {
            phase = .failed("Could not read that photo.")
            return
        }
        await estimate(imageJPEGData: jpeg, preview: image)
    }

    func confirm(estimate: MealEstimate, name: String) async {
        guard let service else {
            phase = .failed("Add your Gemini API key in Settings to log meals from photos.")
            return
        }

        phase = .saving
        do {
            _ = try await service.confirm(estimate: estimate, name: name)
            HapticEngine.shared.play(.mealConfirmed)
            phase = .idle
            NutritionBootstrap.refreshNutrition()
        } catch {
            phase = .failed(PhotoMealService.userMessage(for: error))
        }
    }

    func cancel() {
        phase = .idle
    }

    func dismissError() {
        if case .failed = phase {
            phase = .idle
        }
    }

    private func estimate(imageJPEGData: Data, preview: UIImage?) async {
        guard let service else {
            phase = .failed("Add your Gemini API key in Settings to log meals from photos.")
            return
        }

        phase = .estimating
        do {
            let estimate = try await service.estimate(from: imageJPEGData)
            phase = .confirm(estimate, previewImage: preview)
        } catch {
            phase = .failed(PhotoMealService.userMessage(for: error))
        }
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
