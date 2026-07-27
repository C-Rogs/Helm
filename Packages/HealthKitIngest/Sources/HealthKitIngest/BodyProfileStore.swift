import Core
import Foundation
import Persistence

public struct BodyProfileStore: Sendable {
    public static let metadataKey = "body_profile"

    private let metadata: AppMetadataStore
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    public init(metadata: AppMetadataStore) {
        self.metadata = metadata
    }

    public func load() -> BodyProfile? {
        guard let json = try? metadata.value(forKey: Self.metadataKey) else {
            return nil
        }
        guard
            let data = json.data(using: .utf8),
            let profile = try? jsonDecoder.decode(BodyProfile.self, from: data),
            profile.isComplete
        else {
            return nil
        }
        return profile
    }

    public func save(_ profile: BodyProfile) throws {
        guard profile.isComplete else {
            try metadata.setValue(nil, forKey: Self.metadataKey)
            return
        }
        let data = try jsonEncoder.encode(profile)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NutritionServiceError.encodingFailed
        }
        try metadata.setValue(json, forKey: Self.metadataKey)
    }
}
