import Foundation
import NutritionKit
import Persistence

public struct NutritionTrendStore: Sendable {
    public static let metadataKey = "nutrition_trend_state"

    private let metadata: AppMetadataStore
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    public init(metadata: AppMetadataStore) {
        self.metadata = metadata
    }

    public func load() throws -> NutritionTrendState {
        loadSafely()
    }

    public func loadSafely() -> NutritionTrendState {
        guard let json = try? metadata.value(forKey: Self.metadataKey) else {
            return NutritionTrendState()
        }
        guard
            let data = json.data(using: .utf8),
            let state = try? jsonDecoder.decode(NutritionTrendState.self, from: data)
        else {
            return NutritionTrendState()
        }
        return state
    }

    public func save(_ state: NutritionTrendState) throws {
        let data = try jsonEncoder.encode(state)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NutritionServiceError.encodingFailed
        }
        try metadata.setValue(json, forKey: Self.metadataKey)
    }
}
