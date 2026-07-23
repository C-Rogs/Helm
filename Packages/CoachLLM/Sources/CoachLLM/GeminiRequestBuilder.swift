import Foundation

public struct GeminiStreamRequestBody {
    public let systemInstruction: [String: Any]
    public let contents: [[String: Any]]
    public let generationConfig: [String: Any]

    public func encoded() throws -> Data {
        let payload: [String: Any] = [
            "system_instruction": systemInstruction,
            "contents": contents,
            "generationConfig": generationConfig
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }
}

public struct GeminiGenerateRequestBody {
    public let systemInstruction: [String: Any]
    public let contents: [[String: Any]]
    public let generationConfig: [String: Any]

    public func encoded() throws -> Data {
        let payload: [String: Any] = [
            "system_instruction": systemInstruction,
            "contents": contents,
            "generationConfig": generationConfig
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }
}

public enum GeminiRequestBuilder {
    public static func streamChatBody(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) throws -> GeminiStreamRequestBody {
        GeminiStreamRequestBody(
            systemInstruction: CoachTranscriptBuilder.systemInstruction(systemInstructions),
            contents: CoachTranscriptBuilder.contents(
                systemInstructions: systemInstructions,
                contextBlock: contextBlock,
                userMessage: userMessage,
                thread: thread
            ),
            generationConfig: [
                "temperature": 0.4,
                "maxOutputTokens": 2048
            ]
        )
    }

    public static func sessionAdjustmentBody(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) throws -> GeminiGenerateRequestBody {
        GeminiGenerateRequestBody(
            systemInstruction: CoachTranscriptBuilder.systemInstruction(systemInstructions),
            contents: CoachTranscriptBuilder.contents(
                systemInstructions: systemInstructions,
                contextBlock: contextBlock,
                userMessage: userMessage,
                thread: thread
            ),
            generationConfig: [
                "temperature": 0.2,
                "responseMimeType": "application/json",
                "responseSchema": sessionAdjustmentSchema()
            ]
        )
    }

    public static func mealEstimateBody(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) throws -> GeminiGenerateRequestBody {
        GeminiGenerateRequestBody(
            systemInstruction: CoachTranscriptBuilder.systemInstruction(systemInstructions),
            contents: CoachTranscriptBuilder.contents(
                systemInstructions: systemInstructions,
                contextBlock: contextBlock,
                userMessage: userMessage,
                thread: thread
            ),
            generationConfig: [
                "temperature": 0.2,
                "responseMimeType": "application/json",
                "responseSchema": mealEstimateSchema()
            ]
        )
    }

    public static func morningBriefBody(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) throws -> GeminiGenerateRequestBody {
        GeminiGenerateRequestBody(
            systemInstruction: CoachTranscriptBuilder.systemInstruction(systemInstructions),
            contents: CoachTranscriptBuilder.contents(
                systemInstructions: systemInstructions,
                contextBlock: contextBlock,
                userMessage: userMessage,
                thread: thread
            ),
            generationConfig: [
                "temperature": 0.3,
                "responseMimeType": "application/json",
                "responseSchema": morningBriefSchema()
            ]
        )
    }

    public static func sessionAdjustmentSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "schemaVersion": ["type": "string"],
                "rationale": ["type": "string"],
                "operations": [
                    "type": "array",
                    "items": operationSchema()
                ]
            ],
            "required": ["schemaVersion", "rationale", "operations"]
        ]
    }

    public static func mealEstimateSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "schemaVersion": ["type": "string"],
                "description": ["type": "string"],
                "caloriesKcal": ["type": "number"],
                "proteinG": ["type": "number"],
                "carbsG": ["type": "number"],
                "fatG": ["type": "number"],
                "confidence": [
                    "type": "string",
                    "enum": ["low", "medium", "high"]
                ]
            ],
            "required": [
                "schemaVersion",
                "description",
                "caloriesKcal",
                "proteinG",
                "carbsG",
                "fatG",
                "confidence"
            ]
        ]
    }

    public static func morningBriefSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "schemaVersion": ["type": "string"],
                "narration": ["type": "string"],
                "citationIDs": [
                    "type": "array",
                    "items": ["type": "string"]
                ]
            ],
            "required": ["schemaVersion", "narration", "citationIDs"]
        ]
    }

    private static func operationSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "kind": [
                    "type": "string",
                    "enum": ["swap", "reorder", "adjustSets"]
                ],
                "fromExerciseID": ["type": "string"],
                "toExerciseID": ["type": "string"],
                "excludeExerciseIDs": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "orderedExerciseIDs": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "exerciseID": ["type": "string"],
                "setDelta": ["type": "integer"]
            ],
            "required": ["kind"]
        ]
    }
}
