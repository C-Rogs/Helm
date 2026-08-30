import Foundation

enum ExerciseSeedBundle {
    static func url(named name: String) -> URL? {
        let fileName = "\(name).json"
        let bundles = [Bundle.module, Bundle.main]
        for bundle in bundles {
            if let url = bundle.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "ExerciseSeed"
            ) {
                return url
            }
            let nested = bundle.bundleURL
                .appendingPathComponent("ExerciseSeed")
                .appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: nested.path) {
                return nested
            }
            let root = bundle.bundleURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: root.path) {
                return root
            }
        }
        return nil
    }
}
