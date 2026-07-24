import AVFoundation
import DesignSystem
import SwiftUI
import UIKit

struct BarcodeScannerView: View {
    let onBarcode: (String) -> Void
    let onCancel: () -> Void

    @State private var cameraError: String?

    var body: some View {
        ZStack {
            if let cameraError {
                HelmErrorState(
                    title: "Camera unavailable",
                    message: cameraError,
                    onRetry: nil
                )
                .padding(HelmSpacing.md)
            } else {
                BarcodeScannerRepresentable(onBarcode: onBarcode, onError: { message in
                    cameraError = message
                })
                .ignoresSafeArea()

                VStack {
                    HStack {
                        Button("Cancel", action: onCancel)
                            .buttonStyle(.helmSecondary)
                        Spacer()
                    }
                    .padding(HelmSpacing.md)

                    Spacer()

                    Text("Align the barcode inside the frame")
                        .helmType(.body, color: HelmColor.fg)
                        .padding(.horizontal, HelmSpacing.md)
                        .padding(.vertical, HelmSpacing.sm)
                        .background(HelmColor.surface.opacity(0.88), in: Capsule())
                        .padding(.bottom, HelmSpacing.xl)
                }
            }
        }
        .helmScreenBackground()
        .navigationTitle("Scan barcode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onBarcode: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let controller = BarcodeScannerViewController()
        controller.onBarcode = onBarcode
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

private final class BarcodeScannerViewController: UIViewController {
    var onBarcode: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let metadataDelegate = BarcodeMetadataDelegate()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        metadataDelegate.onBarcode = { [weak self] barcode in
            self?.session.stopRunning()
            self?.onBarcode?(barcode)
        }
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startSession()
                    } else {
                        self?.onError?("Camera access is required to scan barcodes.")
                    }
                }
            }
        default:
            onError?("Camera access is required to scan barcodes. Enable it in Settings.")
        }
    }

    private func startSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            onError?("This device does not have a usable camera.")
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input) else {
            onError?("Could not start the camera.")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            onError?("Could not start the barcode reader.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(metadataDelegate, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39, .qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
}

private final class BarcodeMetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var onBarcode: ((String) -> Void)?
    private var hasEmittedBarcode = false

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasEmittedBarcode,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              !value.isEmpty
        else {
            return
        }

        hasEmittedBarcode = true
        onBarcode?(value)
    }
}

#Preview("Barcode scanner") {
    NavigationStack {
        BarcodeScannerView(onBarcode: { _ in }, onCancel: {})
    }
    .helmTheme()
}
