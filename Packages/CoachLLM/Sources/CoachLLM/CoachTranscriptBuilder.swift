import Foundation

public enum CoachTranscriptBuilder {
    public static func contents(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) -> [[String: Any]] {
        var contents: [[String: Any]] = []

        if !contextBlock.isEmpty {
            contents.append([
                "role": "user",
                "parts": [["text": "Context:\n\(contextBlock)"]]
            ])
            contents.append([
                "role": "model",
                "parts": [["text": "Understood."]]
            ])
        }

        // Avoid duplicating the current user turn when it was already appended to thread.
        let history = Self.historyExcludingTrailingDuplicate(
            messages: thread.messages,
            userMessage: userMessage
        )
        for message in history {
            let role = message.role == .assistant ? "model" : "user"
            contents.append([
                "role": role,
                "parts": [["text": message.text]]
            ])
        }

        contents.append([
            "role": "user",
            "parts": [["text": userMessage]]
        ])

        _ = systemInstructions
        return contents
    }

    /// Drops a trailing user message that exactly matches `userMessage` (or its stored raw form).
    public static func historyExcludingTrailingDuplicate(
        messages: [CoachMessage],
        userMessage: String
    ) -> [CoachMessage] {
        guard let last = messages.last, last.role == .user else {
            return messages
        }
        let lastText = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if lastText == current {
            return Array(messages.dropLast())
        }
        // Dictation: stored transcript vs framed coach user message.
        if current.contains(lastText), current.contains("[Food dictation") {
            return Array(messages.dropLast())
        }
        return messages
    }

    public static func systemInstruction(_ systemInstructions: String) -> [String: Any] {
        ["parts": [["text": systemInstructions]]]
    }

    public static func mealPhotoContents(
        imageJPEGBase64: String,
        userMessage: String
    ) -> [[String: Any]] {
        [
            [
                "role": "user",
                "parts": [
                    [
                        "inline_data": [
                            "mime_type": "image/jpeg",
                            "data": imageJPEGBase64
                        ]
                    ],
                    ["text": userMessage]
                ]
            ]
        ]
    }
}
