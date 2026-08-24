import Foundation

/// Abstraction over iCloud Drive (or a local directory in tests).
public protocol CloudBackupFileStore: Sendable {
    var isAvailable: Bool { get }
    func prepareDirectory() throws
    func write(data: Data, fileName: String) throws
    func read(fileName: String, downloadTimeout: TimeInterval) throws -> Data?
    func remove(fileName: String) throws
}

extension CloudBackupFileStore {
    public func read(fileName: String) throws -> Data? {
        try read(fileName: fileName, downloadTimeout: 0)
    }
}

/// Writes under the app's ubiquity Documents/HelmBackup folder.
public struct UbiquityCloudBackupFileStore: CloudBackupFileStore, Sendable {
    public static let defaultContainerIdentifier = "iCloud.com.cameronro.helm"
    public static let backupFolderName = "HelmBackup"
    public static let profileFileName = "helm-profile.json"
    public static let historyFileName = "helm-training-history.json"
    public static let nutritionFileName = "helm-nutrition.json"

    private let containerIdentifier: String

    public init(containerIdentifier: String = defaultContainerIdentifier) {
        self.containerIdentifier = containerIdentifier
    }

    public var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
            && FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) != nil
    }

    public func prepareDirectory() throws {
        let directory = try backupDirectoryURL()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func write(data: Data, fileName: String) throws {
        try prepareDirectory()
        let url = try backupDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw CloudBackupError.writeFailed(error.localizedDescription)
        }
    }

    public func read(fileName: String, downloadTimeout: TimeInterval = 0) throws -> Data? {
        let url = try backupDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
        if downloadTimeout > 0 {
            try ensureDownloaded(at: url, fileName: fileName, timeout: downloadTimeout)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw CloudBackupError.readFailed(error.localizedDescription)
        }
    }

    public func remove(fileName: String) throws {
        let url = try backupDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func backupDirectoryURL() throws -> URL {
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw CloudBackupError.iCloudUnavailable
        }
        return root
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(Self.backupFolderName, isDirectory: true)
    }

    private func ensureDownloaded(at url: URL, fileName: String, timeout: TimeInterval) throws {
        let fileManager = FileManager.default

        func isDownloaded() -> Bool {
            guard fileManager.fileExists(atPath: url.path) else { return false }
            guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
                  values.isUbiquitousItem == true else {
                return true
            }
            switch values.ubiquitousItemDownloadingStatus {
            case .current, .downloaded:
                return true
            default:
                return false
            }
        }

        if isDownloaded() { return }

        // If the file doesn't exist at all in the ubiquity container, don't wait.
        let directory = url.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directory.path),
           let contents = try? fileManager.contentsOfDirectory(atPath: directory.path),
           !contents.contains(fileName) {
            return
        }

        try? fileManager.startDownloadingUbiquitousItem(at: url)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isDownloaded() { return }
            Thread.sleep(forTimeInterval: 0.25)
        }

        throw CloudBackupError.downloadTimedOut(fileName)
    }
}

/// Local directory store for unit tests (same file names as ubiquity).
public struct LocalDirectoryCloudBackupFileStore: CloudBackupFileStore, Sendable {
    private let rootURL: URL
    public let isAvailable: Bool

    public init(rootURL: URL, isAvailable: Bool = true) {
        self.rootURL = rootURL
        self.isAvailable = isAvailable
    }

    public func prepareDirectory() throws {
        if !FileManager.default.fileExists(atPath: rootURL.path) {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    public func write(data: Data, fileName: String) throws {
        try prepareDirectory()
        let url = rootURL.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: url, options: .atomic)
    }

    public func read(fileName: String, downloadTimeout: TimeInterval = 0) throws -> Data? {
        let url = rootURL.appendingPathComponent(fileName, isDirectory: false)
        _ = downloadTimeout
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func remove(fileName: String) throws {
        let url = rootURL.appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
