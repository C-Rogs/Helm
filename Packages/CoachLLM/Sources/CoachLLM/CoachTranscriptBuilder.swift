import Foundation

public enum CoachTranscriptBuilder {
    public static func contents(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState,
        freshnessSuffix: String? = nil
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
        let contextMessages = thread.messagesForContext()
        let history = Self.historyExcludingTrailingDuplicate(
            messages: contextMessages,
            userMessage: userMessage
        )
        for message in history {
            let role: String
            switch message.role {
            case .assistant: role = "model"
            case .system: role = "user"  // Gemini doesn't support system role in turns
            case .user: role = "user"
            }
            contents.append([
                "role": role,
                "parts": [["text": message.text]]
            ])
        }

        // Appended as trailing user message after history to preserve
        // Gemini implicit caching on the context block prefix.
        if let suffix = freshnessSuffix, !suffix.isEmpty {
            contents.append([
                "role": "user",
                "parts": [["text": suffix]]
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
