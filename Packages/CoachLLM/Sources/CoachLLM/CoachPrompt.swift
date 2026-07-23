import Foundation

/// Assembled coach input split for provider APIs.
public struct CoachPrompt: Sendable, Equatable {
    public let systemInstructions: String
    public let contextBlock: String
    public let estimatedTokens: Int
    public let includedDayCount: Int
    public let droppedDayCount: Int

    public init(
        systemInstructions: String,
        contextBlock: String,
        estimatedTokens: Int,
        includedDayCount: Int,
        droppedDayCount: Int
    ) {
        self.systemInstructions = systemInstructions
        self.contextBlock = contextBlock
        self.estimatedTokens = estimatedTokens
        self.includedDayCount = includedDayCount
        self.droppedDayCount = droppedDayCount
    }
}

public typealias Prompt = CoachPrompt
