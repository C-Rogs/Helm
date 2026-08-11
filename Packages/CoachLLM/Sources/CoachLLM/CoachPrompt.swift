import Foundation

/// Assembled coach input split for provider APIs.
public struct CoachPrompt: Sendable, Equatable {
    public let systemInstructions: String
    public let contextBlock: String
    public let estimatedTokens: Int
    public let includedDayCount: Int
    public let droppedDayCount: Int
    /// Staleness suffix for CoachTranscriptBuilder, placed after history
    /// but before the current user message (preserves Gemini caching).
    public let freshnessSuffix: String?

    public init(
        systemInstructions: String,
        contextBlock: String,
        estimatedTokens: Int,
        includedDayCount: Int,
        droppedDayCount: Int,
        freshnessSuffix: String? = nil
    ) {
        self.systemInstructions = systemInstructions
        self.contextBlock = contextBlock
        self.estimatedTokens = estimatedTokens
        self.includedDayCount = includedDayCount
        self.droppedDayCount = droppedDayCount
        self.freshnessSuffix = freshnessSuffix
    }
}

public typealias Prompt = CoachPrompt
