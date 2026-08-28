import Foundation

/// Gemini REST encoding of `CoachCatalogToolName`. Other providers ship their own encoder.
public enum GeminiChatTools {
    public static func streamToolConfig() -> [String: Any] {
        [
            "functionCallingConfig": [
                "mode": "AUTO"
            ]
        ]
    }

    public static func streamTools() -> [[String: Any]] {
        [
            ["functionDeclarations": functionDeclarations()]
        ]
    }

    public static func functionDeclarations() -> [[String: Any]] {
        [
            foodLogDeclaration(),
            mealCopyDeclaration(),
            workoutStartDeclaration(),
            memoryAdjustmentDeclaration(),
            settingsAdjustmentDeclaration(),
            reactiveDeloadDeclaration(),
            planRegenerateDeclaration()
        ]
    }

    private static func foodLogDeclaration() -> [String: Any] {
        [
            "name": CoachCatalogToolName.foodLog.rawValue,
            "description": """
            Propose a meal diary write (log, edit, or delete). The app shows a confirm card; \
            do not wait for a verbal yes. Include items with estimatedGrams for dictated meals.
            """,
            "parameters": [
                "type": "object",
                "properties": [
                    "reply": stringProperty("Short athlete-facing line."),
                    "action": [
                        "type": "string",
                        "enum": ["log", "edit", "delete"]
                    ],
                    "mealID": stringProperty("Required for edit or single delete."),
                    "description": stringProperty("Meal name."),
                    "bucket": [
                        "type": "string",
                        "enum": ["breakfast", "lunch", "dinner", "snacks"]
                    ],
                    "caloriesKcal": ["type": "number"],
                    "proteinG": ["type": "number"],
                    "carbsG": ["type": "number"],
                    "fatG": ["type": "number"],
                    "helmDay": stringProperty("YYYY-MM-DD. Defaults to today."),
                    "items": [
                        "type": "array",
                        "items": ingredientItemSchema()
                    ],
                    "implicitFats": [
                        "type": "array",
                        "items": ingredientItemSchema()
                    ],
                    "portionNotes": stringProperty()
                ],
                "required": ["action"]
            ]
        ]
    }

    private static func mealCopyDeclaration() -> [String: Any] {
        [
            "name": CoachCatalogToolName.mealCopy.rawValue,
            "description": "Propose copying one meal bucket onto another day. App shows a confirm card.",
            "parameters": [
                "type": "object",
                "properties": [
                    "reply": stringProperty(),
                    "sourceHelmDay": stringProperty("YYYY-MM-DD"),
                    "sourceBucket": bucketProperty(),
                    "targetHelmDay": stringProperty("YYYY-MM-DD"),
                    "targetBucket": bucketProperty()
                ],
                "required": ["sourceHelmDay", "sourceBucket", "targetHelmDay", "targetBucket"]
            ]
        ]
    }

    private static func workoutStartDeclaration() -> [String: Any] {
        [
            "name": CoachCatalogToolName.workoutStart.rawValue,
            "description": """
            Propose starting a session after the athlete clearly wants to start. \
            Include every agreed exercise and sets for a custom session. \
            Omit exercises only to start today's unchanged engine prescription.
            """,
            "parameters": [
                "type": "object",
                "properties": [
                    "helmDay": stringProperty("YYYY-MM-DD"),
                    "title": stringProperty(),
                    "useAdjustedPrescription": ["type": "boolean"],
                    "exercises": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "name": stringProperty(),
                                "restSeconds": ["type": "integer"],
                                "sets": [
                                    "type": "array",
                                    "items": [
                                        "type": "object",
                                        "properties": [
                                            "setType": [
                                                "type": "string",
                                                "enum": [
                                                    "warmup",
                                                    "normal",
                                                    "drop_set",
                                                    "failure",
                                                    "bodyweight"
                                                ]
                                            ],
                                            "reps": ["type": "integer"],
                                            "massKg": ["type": "number"],
                                            "rpe": ["type": "number"]
                                        ],
                                        "required": ["setType", "reps", "massKg"]
                                    ]
                                ]
                            ],
                            "required": ["name"]
                        ]
                    ]
                ]
            ]
        ]
    }

    private static func memoryAdjustmentDeclaration() -> [String: Any] {
        [
            "name": CoachCatalogToolName.memoryAdjustment.rawValue,
            "description": "Propose saving or clearing a standing constraint. App shows a confirm card.",
            "parameters": [
                "type": "object",
                "properties": [
                    "reply": stringProperty(),
                    "action": [
                        "type": "string",
                        "enum": ["add", "clear"]
                    ],
                    "standingConstraintNote": stringProperty("Required for add."),
                    "untilDate": stringProperty("YYYY-MM-DD"),
                    "joint": [
                        "type": "string",
                        "enum": [
                            "shoulder", "knee", "hip", "elbow",
                            "wrist", "back", "ankle", "neck"
                        ]
                    ],
                    "rationale": stringProperty()
                ],
                "required": ["action"]
            ]
        ]
    }

    private static func settingsAdjustmentDeclaration() -> [String: Any] {
        [
            "name": CoachCatalogToolName.settingsAdjustment.rawValue,
            "description": "Propose changing training phase, weekly rate, or emphasis. App shows a confirm card.",
            "parameters": [
                "type": "object",
                "properties": [
                    "reply": stringProperty(),
                    "phase": [
                        "type": "string",
                        "enum": ["cut", "gain", "maintain"]
                    ],
                    "weeklyRateKg": ["type": "number"],
                    "emphasis": stringProperty("Free-form athlete intent."),
                    "rationale": stringProperty()
                ]
            ]
        ]
    }

    private static func reactiveDeloadDeclaration() -> [String: Any] {
        [
            "name": CoachCatalogToolName.reactiveDeload.rawValue,
            "description": "Propose confirming or dismissing a pending engine deload week.",
            "parameters": [
                "type": "object",
                "properties": [
                    "reply": stringProperty(),
                    "action": [
                        "type": "string",
                        "enum": ["confirm", "dismiss"]
                    ]
                ],
                "required": ["action"]
            ]
        ]
    }

    private static func planRegenerateDeclaration() -> [String: Any] {
        [
            "name": CoachCatalogToolName.planRegenerate.rawValue,
            "description": "Propose regenerating today's prescription from the engine.",
            "parameters": [
                "type": "object",
                "properties": [
                    "reply": stringProperty()
                ]
            ]
        ]
    }

    private static func ingredientItemSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": stringProperty(),
                "estimatedGrams": ["type": "number"],
                "confidence": [
                    "type": "string",
                    "enum": ["low", "medium", "high"]
                ]
            ],
            "required": ["name", "estimatedGrams", "confidence"]
        ]
    }

    private static func bucketProperty() -> [String: Any] {
        [
            "type": "string",
            "enum": ["breakfast", "lunch", "dinner", "snacks"]
        ]
    }

    private static func stringProperty(_ description: String? = nil) -> [String: Any] {
        var property: [String: Any] = ["type": "string"]
        if let description, !description.isEmpty {
            property["description"] = description
        }
        return property
    }
}
