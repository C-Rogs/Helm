import Foundation

/// Abstraction over iCloud Drive (or a local directory in tests).
public protocol CloudBackupFileStore: Sendable {
    var isAvailable: Bool { get }
    func prepareDirectory() throws
    func write(data: Data, fileName: String) throws
    func read(fileName: String) throws -> Data?
    func remove(fileName: String) throws
}

/// Writes under the app's ubiquity Documents/HelmBackup folder.
public struct UbiquityCloudBackupFileStore: CloudBackupFileStore, Sendable {
    public static let defaultContainerIdentifier = "iCloud.com.cameronro.helm"
    public static let backupFolderName = "HelmBackup"
    public static let profileFileName = "helm-profile.json"
    public static let historyFileName = "helm-training-history.json"

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

    public func read(fileName: String) throws -> Data? {
        let url = try backupDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
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

    public func read(fileName: String) throws -> Data? {
        let url = rootURL.appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func remove(fileName: String) throws {
        let url = rootURL.appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
