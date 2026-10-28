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

        // The reference pack belongs in the system instruction. It is not a turn
        // the athlete sent, and the model must not answer it before they speak.
        _ = systemInstructions
        _ = contextBlock
        _ = freshnessSuffix

        let contextMessages = thread.messagesForContext().filter { message in
            if message.role == .assistant {
                return !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }
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
        if current.contains("[Reply failed]"), current.contains(lastText) {
            return Array(messages.dropLast())
        }
        return messages
    }

    public static func systemInstruction(
        _ systemInstructions: String,
        reference: String? = nil
    ) -> [String: Any] {
        var text = systemInstructions
        if let reference {
            let pack = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pack.isEmpty {
                text += "\n\n# Reference pack\nHealth data and the training plan. Not a message from the athlete. Answer their messages. Use a fact from this pack when their message needs it. Do not open with the pack, and do not let it replace what they just said.\n\n\(pack)"
            }
        }
        return ["parts": [["text": text]]]
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
