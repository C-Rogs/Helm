@preconcurrency import AVFoundation
import Core
import SwiftUI
import UIKit

enum MealDepthPortionAssist {
    /// Typical overhead plate distance for gram reference calibration.
    static let referenceDepthMeters = 0.32
    static let minScaleFactor = 0.75
    static let maxScaleFactor = 1.35

    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) != nil
    }

    static func derive(from depthData: AVDepthData, imageSize: CGSize) -> MealPortionAssistContext? {
        let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let pixelBuffer = converted.depthDataMap
        guard let medianDepth = medianDepthMeters(in: pixelBuffer, roiFraction: 0.4),
              medianDepth > 0.05,
              medianDepth < 2.0 else {
            return nil
        }

        let rawScale = referenceDepthMeters / medianDepth
        let clampedScale = min(max(rawScale, minScaleFactor), maxScaleFactor)
        return MealPortionAssistContext(
            gramScaleFactor: clampedScale,
            medianDepthMeters: medianDepth,
            referenceDepthMeters: referenceDepthMeters
        )
    }

    private static func medianDepthMeters(in pixelBuffer: CVPixelBuffer, roiFraction: CGFloat) -> Double? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0,
              let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let roiWidth = max(1, Int(CGFloat(width) * roiFraction))
        let roiHeight = max(1, Int(CGFloat(height) * roiFraction))
        let startX = (width - roiWidth) / 2
        let startY = (height - roiHeight) / 2

        var samples: [Float] = []
        samples.reserveCapacity(roiWidth * roiHeight)

        for row in startY ..< (startY + roiHeight) {
            let rowStart = baseAddress.advanced(by: row * rowBytes).assumingMemoryBound(to: Float.self)
            for column in startX ..< (startX + roiWidth) {
                let depth = rowStart[column]
                if depth.isFinite, depth > 0.05, depth < 2.0 {
                    samples.append(depth)
                }
            }
        }

        guard !samples.isEmpty else { return nil }
        samples.sort()
        let middle = samples.count / 2
        if samples.count.isMultiple(of: 2) {
            return Double((samples[middle - 1] + samples[middle]) / 2)
        }
        return Double(samples[middle])
    }
}

struct MealDepthCameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage, MealPortionAssistContext?) -> Void

    func makeUIViewController(context: Context) -> MealDepthCameraViewController {
        let controller = MealDepthCameraViewController()
        controller.onCapture = { image, assist in
            onCapture(image, assist)
            dismiss()
        }
        controller.onCancel = { dismiss() }
        return controller
    }

    func updateUIViewController(_ uiViewController: MealDepthCameraViewController, context: Context) {}
}

final class MealDepthCameraViewController: UIViewController {
    var onCapture: ((UIImage, MealPortionAssistContext?) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isCapturing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
        configureControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !session.isRunning else { return }
        session.startRunning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard session.isRunning else { return }
        session.stopRunning()
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(photoOutput)
        if photoOutput.isDepthDataDeliverySupported {
            photoOutput.isDepthDataDeliveryEnabled = true
        }
        session.commitConfiguration()

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer
    }

    private func configureControls() {
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.tintColor = .white
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)

        let shutterButton = UIButton(type: .system)
        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 34
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        view.addSubview(shutterButton)

        if MealDepthPortionAssist.isAvailable {
            let lidarLabel = UILabel()
            lidarLabel.text = "LiDAR portion assist"
            lidarLabel.font = .preferredFont(forTextStyle: .footnote)
            lidarLabel.textColor = .white.withAlphaComponent(0.9)
            lidarLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(lidarLabel)

            NSLayoutConstraint.activate([
                lidarLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                lidarLabel.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -16)
            ])
        }

        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            shutterButton.widthAnchor.constraint(equalToConstant: 68),
            shutterButton.heightAnchor.constraint(equalToConstant: 68)
        ])
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func shutterTapped() {
        guard !isCapturing else { return }
        isCapturing = true

        let settings = AVCapturePhotoSettings()
        if photoOutput.isDepthDataDeliverySupported {
            settings.isDepthDataDeliveryEnabled = true
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension MealDepthCameraViewController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        defer {
            Task { @MainActor in
                isCapturing = false
            }
        }
        guard error == nil,
              let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            return
        }

        let assist = photo.depthData.flatMap {
            MealDepthPortionAssist.derive(from: $0, imageSize: image.size)
        }
        Task { @MainActor in
            onCapture?(image, assist)
        }
    }
}
