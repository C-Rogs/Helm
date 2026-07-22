#if DEBUG
import CoachLLM
import Diagnostics
import Foundation

enum SecretsBootstrap {
    private static let secretsDirectoryName = "Secrets"

    static func run() async {
        let logger = helmLogger(category: .coachLLM)
        let store = APIKeyStore()

        guard let secretsDirectory = secretsDirectoryURL() else {
            logger.warning("Secrets bootstrap skipped: \(secretsDirectoryName, privacy: .public) not in app bundle")
            await DiagnosticsLog.shared.record(
                category: .coachLLM,
                level: .info,
                message: "Secrets bootstrap skipped: Secrets/ not bundled",
                context: [
                    "hint": "Copy Secrets.example/ to Secrets/ at repo root and add your keys",
                    "phase": "M0.6"
                ]
            )
            return
        }

        var loadedKinds: [String] = []
        var missingKinds: [String] = []

        for kind in APIKeyKind.allCases {
            let fileURL = secretsDirectory.appendingPathComponent(kind.secretsFileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                missingKinds.append(kind.rawValue)
                continue
            }

            do {
                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    missingKinds.append(kind.rawValue)
                    await DiagnosticsLog.shared.record(
                        category: .coachLLM,
                        level: .info,
                        message: "Secrets bootstrap skipped empty key file",
                        context: ["key": kind.rawValue, "file": kind.secretsFileName]
                    )
                    continue
                }

                try store.save(trimmed, kind: kind)
                loadedKinds.append(kind.rawValue)
            } catch {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .coachLLM,
                    message: "Secrets bootstrap failed to load key file",
                    context: ["key": kind.rawValue, "file": kind.secretsFileName]
                )
            }
        }

        if loadedKinds.isEmpty {
            logger.warning("Secrets bootstrap found no API keys to load")
            await DiagnosticsLog.shared.record(
                category: .coachLLM,
                level: .info,
                message: "Secrets bootstrap found no API keys",
                context: [
                    "missing": missingKinds.joined(separator: ","),
                    "hint": "Add gemini.key under Secrets/ and rebuild Debug"
                ]
            )
            return
        }

        logger.info("Secrets bootstrap loaded \(loadedKinds.count, privacy: .public) key(s) into Keychain")
        await DiagnosticsLog.shared.record(
            category: .coachLLM,
            level: .info,
            message: "Secrets bootstrap loaded keys into Keychain",
            context: [
                "loaded": loadedKinds.joined(separator: ","),
                "missing": missingKinds.joined(separator: ","),
                "phase": "M0.6"
            ]
        )
    }

    private static func secretsDirectoryURL() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }

        let directoryURL = resourceURL.appendingPathComponent(secretsDirectoryName, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return directoryURL
    }
}
#endif
