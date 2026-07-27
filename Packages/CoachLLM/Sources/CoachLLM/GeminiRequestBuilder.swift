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

    public static func mealEstimatePhotoBody(
        systemInstructions: String,
        imageJPEGBase64: String,
        userMessage: String = "Estimate the meal macros from this photo."
    ) throws -> GeminiGenerateRequestBody {
        GeminiGenerateRequestBody(
            systemInstruction: CoachTranscriptBuilder.systemInstruction(systemInstructions),
            contents: CoachTranscriptBuilder.mealPhotoContents(
                imageJPEGBase64: imageJPEGBase64,
                userMessage: userMessage
            ),
            generationConfig: [
                "temperature": 0.2,
                "responseMimeType": "application/json",
                "responseSchema": mealEstimateSchema()
            ]
        )
    }

    public static func mealDecompositionPhotoBody(
        systemInstructions: String,
        imageJPEGBase64: String,
        userMessage: String = "Decompose this meal photo into ingredients and estimated grams."
    ) throws -> GeminiGenerateRequestBody {
        GeminiGenerateRequestBody(
            systemInstruction: CoachTranscriptBuilder.systemInstruction(systemInstructions),
            contents: CoachTranscriptBuilder.mealPhotoContents(
                imageJPEGBase64: imageJPEGBase64,
                userMessage: userMessage
            ),
            generationConfig: [
                "temperature": 0.2,
                "responseMimeType": "application/json",
                "responseSchema": mealDecompositionSchema()
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
        sessionAdjustmentV2Schema()
    }

    public static func sessionAdjustmentV2Schema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "schemaVersion": schemaVersionProperty(CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue),
                "reply": ["type": "string"],
                "rationale": ["type": "string"],
                "operations": [
                    "type": "array",
                    "items": operationSchemaV2()
                ]
            ],
            "required": ["schemaVersion", "reply", "operations"]
        ]
    }

    public static func sessionAdjustmentV1Schema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "schemaVersion": schemaVersionProperty(CoachOutputSchemaVersion.sessionAdjustmentV1.rawValue),
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
                "schemaVersion": schemaVersionProperty(CoachOutputSchemaVersion.mealEstimateV1.rawValue),
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

    public static func mealDecompositionSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "schemaVersion": schemaVersionProperty(CoachOutputSchemaVersion.mealDecompositionV1.rawValue),
                "mealDescription": ["type": "string"],
                "items": [
                    "type": "array",
                    "items": decompositionItemSchema()
                ],
                "implicitFats": [
                    "type": "array",
                    "items": decompositionItemSchema()
                ],
                "portionNotes": ["type": "string"]
            ],
            "required": ["schemaVersion", "mealDescription", "items", "implicitFats"]
        ]
    }

    private static func decompositionItemSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "estimatedGrams": ["type": "number"],
                "confidence": [
                    "type": "string",
                    "enum": ["low", "medium", "high"]
                ]
            ],
            "required": ["name", "estimatedGrams", "confidence"]
        ]
    }

    public static func morningBriefSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "schemaVersion": schemaVersionProperty(CoachOutputSchemaVersion.briefV1.rawValue),
                "narration": ["type": "string"],
                "citationIDs": [
                    "type": "array",
                    "items": ["type": "string"]
                ]
            ],
            "required": ["schemaVersion", "narration", "citationIDs"]
        ]
    }

    private static func schemaVersionProperty(_ version: String) -> [String: Any] {
        [
            "type": "string",
            "enum": [version]
        ]
    }

    private static func operationSchemaV2() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "kind": [
                    "type": "string",
                    "enum": ["swap", "reorder", "adjustSets", "adjustLoad", "adjustRPE"]
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
                "setDelta": ["type": "integer"],
                "massDeltaKg": ["type": "number"],
                "targetMassKg": ["type": "number"],
                "rpeDelta": ["type": "number"],
                "targetRPE": ["type": "number"]
            ],
            "required": ["kind"]
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
