import Diagnostics
import UIKit

enum ExportEnvironmentFactory {
    static func current(schemaVersion: Int = 0) -> ExportEnvironment {
        let bundle = Bundle.main
        let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        return ExportEnvironment(
            appVersion: appVersion,
            buildNumber: buildNumber,
            schemaVersion: schemaVersion,
            deviceModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion
        )
    }
}
