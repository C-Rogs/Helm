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
            planRegenerateDeclaration(),
            mealQueryDeclaration(),
            recoveryQueryDeclaration(),
            calendarQueryDeclaration(),
            trendsQueryDeclaration(),
            workoutQueryDeclaration(),
            nutritionQueryDeclaration()
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

    private static func mealQueryDeclaration() -> [String: Any] {
        queryDeclaration(
            name: .mealQuery,
            description: """
            Fetch past meals, a usual bucket, or a day summary. The app runs this and \
            sends macros back. Use before meal_copy. Do not log a meal with this tool.
            """,
            queryTypes: ["bucketOnDay", "usualForBucket", "daySummary"],
            extraProperties: [
                "bucket": [
                    "type": "string",
                    "enum": ["breakfast", "lunch", "dinner", "snacks"]
                ]
            ]
        )
    }

    private static func recoveryQueryDeclaration() -> [String: Any] {
        queryDeclaration(
            name: .recoveryQuery,
            description: """
            Fetch recovery, HRV, or sleep detail beyond Today in context. \
            The app runs this and sends numbers back.
            """,
            queryTypes: ["today", "day", "range", "sleepDetail"]
        )
    }

    private static func calendarQueryDeclaration() -> [String: Any] {
        queryDeclaration(
            name: .calendarQuery,
            description: """
            Fetch EventKit events and why a day is marked busy. \
            Week Ahead busy= lines are not an agenda.
            """,
            queryTypes: ["today", "day", "range", "weekAhead"]
        )
    }

    private static func trendsQueryDeclaration() -> [String: Any] {
        queryDeclaration(
            name: .trendsQuery,
            description: "Fetch multi-week trends (TRIMP, weight, E1RM, energy balance, readiness).",
            queryTypes: ["trimp", "weight", "e1rm", "energyBalance", "readiness", "all"],
            extraProperties: [
                "exerciseName": stringProperty("Required for a specific e1rm lift.")
            ]
        )
    }

    private static func workoutQueryDeclaration() -> [String: Any] {
        queryDeclaration(
            name: .workoutQuery,
            description: "Fetch a completed session or recent training logs. The app runs this and sends results back.",
            queryTypes: ["latestCompleted", "onDay", "includingCardio"]
        )
    }

    private static func nutritionQueryDeclaration() -> [String: Any] {
        queryDeclaration(
            name: .nutritionQuery,
            description: """
            Fetch engine TDEE, trend weight, intake history, or weekly budget numbers \
            not shown in the Nutrition Diary context.
            """,
            queryTypes: ["today", "day", "range", "weeklyBudget"]
        )
    }

    private static func queryDeclaration(
        name: CoachCatalogToolName,
        description: String,
        queryTypes: [String],
        extraProperties: [String: Any] = [:]
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "queryType": [
                "type": "string",
                "enum": queryTypes
            ],
            "helmDay": stringProperty("YYYY-MM-DD"),
            "lookbackDays": ["type": "integer"]
        ]
        for (key, value) in extraProperties {
            properties[key] = value
        }
        return [
            "name": name.rawValue,
            "description": description,
            "parameters": [
                "type": "object",
                "properties": properties,
                "required": ["queryType"]
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
