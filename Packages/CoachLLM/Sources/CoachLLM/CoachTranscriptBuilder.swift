import Foundation

enum CoachTranscriptBuilder {
    static func contents(
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

        for message in thread.messages {
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

    static func systemInstruction(_ systemInstructions: String) -> [String: Any] {
        ["parts": [["text": systemInstructions]]]
    }
}
