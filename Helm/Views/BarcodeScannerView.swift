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
    private let sessionQueue = DispatchQueue(label: "helm.barcode.session")
    private let metadataDelegate = BarcodeMetadataDelegate()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        metadataDelegate.onBarcode = { [weak self] barcode in
            self?.sessionQueue.async {
                if self?.session.isRunning == true {
                    self?.session.stopRunning()
                }
            }
            self?.onBarcode?(barcode)
        }
        configureSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            self?.startRunningOnSessionQueue()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
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
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.isConfigured {
                self.startRunningOnSessionQueue()
                return
            }

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device)
            else {
                DispatchQueue.main.async {
                    self.onError?("This device does not have a usable camera.")
                }
                return
            }

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            guard self.session.canAddInput(input) else {
                DispatchQueue.main.async {
                    self.onError?("Could not start the camera.")
                }
                return
            }
            self.session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard self.session.canAddOutput(output) else {
                DispatchQueue.main.async {
                    self.onError?("Could not start the barcode reader.")
                }
                return
            }
            self.session.addOutput(output)
            output.setMetadataObjectsDelegate(self.metadataDelegate, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39, .qr]
            self.isConfigured = true
        }

        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured else { return }
            self.startRunningOnSessionQueue()
            self.installPreviewIfNeeded()
        }
    }

    private func startRunningOnSessionQueue() {
        guard isConfigured, !session.isRunning else { return }
        session.startRunning()
    }

    private func installPreviewIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.previewLayer == nil else { return }
            let preview = AVCaptureVideoPreviewLayer(session: self.session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = self.view.layer.bounds
            self.view.layer.insertSublayer(preview, at: 0)
            self.previewLayer = preview
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
