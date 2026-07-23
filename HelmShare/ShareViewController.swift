import ExportKit
import os
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let logger = Logger(subsystem: "com.cameronro.helm.share", category: "schemaV2")
    private var didStartProcessing = false
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        spinner.startAnimating()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartProcessing else { return }
        didStartProcessing = true
        Task { await processShare() }
    }

    @MainActor
    private func processShare() async {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            logger.error("Share failed: no extension items")
            completeRequest()
            return
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if let data = await loadExportData(from: provider) {
                    do {
                        let payload = try SchemaV2Decoder.decode(from: data)
                        try SchemaV2Validation.validate(payload)
                        try AppGroupExportStore.writeLatestExport(data)
                        AppGroupExportStore.markPendingImport()
                        logger.info("Share wrote export with \(payload.logs.count) day(s)")
                        openHelmApp()
                        return
                    } catch {
                        logger.error("Share import failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        logger.error("Share failed: no valid bioharvest export found")
        completeRequest()
    }

    private func loadExportData(from provider: NSItemProvider) async -> Data? {
        var typeIdentifiers = provider.registeredTypeIdentifiers
        let preferredTypes = [
            UTType.json.identifier,
            UTType.plainText.identifier,
            UTType.fileURL.identifier,
            "public.data"
        ]
        for preferred in preferredTypes where !typeIdentifiers.contains(preferred) {
            typeIdentifiers.append(preferred)
        }

        for typeID in typeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeID) {
            if let data = await loadDataRepresentation(from: provider, typeID: typeID) {
                return data
            }
            if let data = await loadItem(from: provider, typeID: typeID) {
                return data
            }
        }
        return nil
    }

    private func loadDataRepresentation(from provider: NSItemProvider, typeID: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    private func loadItem(from provider: NSItemProvider, typeID: String) async -> Data? {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let data: Data?
                    if let rawData = item as? Data {
                        data = rawData
                    } else if let string = item as? String {
                        data = string.data(using: .utf8)
                    } else if let url = item as? URL {
                        let didAccess = url.startAccessingSecurityScopedResource()
                        defer {
                            if didAccess {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
                        data = try? Data(contentsOf: url)
                    } else {
                        data = nil
                    }

                    continuation.resume(returning: data)
                }
            }
        } catch {
            return nil
        }
    }

    private func openHelmApp() {
        guard let url = AppGroupExportStore.importURL else {
            completeRequest()
            return
        }

        extensionContext?.open(url) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.completeRequest()
            }
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
