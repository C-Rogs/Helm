import CoachLLM
import Foundation
import Testing
@testable import Persistence

@Suite("Coach history export")
struct CoachHistoryExportTests {
    @Test("formats roles and clips long transcripts")
    func formatsAndClips() throws {
        let store = try PersistenceStore.inMemory()
        _ = try store.chat.append(ChatMessageInsert(role: .user, text: "hello", promptVersion: "chat.v1"))
        _ = try store.chat.append(ChatMessageInsert(role: .assistant, text: "hi", promptVersion: "chat.v1"))
        let markdown = CoachHistoryExport.markdown(from: try store.chat.fetchAll())
        #expect(markdown.contains("### Chat"))
        #expect(markdown.contains("**You:** hello"))
        #expect(markdown.contains("**Coach:** hi"))

        _ = try store.chat.append(
            ChatMessageInsert(role: .user, text: "fill in the weights", promptVersion: "session.v2", surface: .train)
        )
        let combined = CoachHistoryExport.markdown(
            chat: try store.chat.fetchAll(surface: .chat),
            train: try store.chat.fetchAll(surface: .train)
        )
        #expect(combined.contains("### Chat"))
        #expect(combined.contains("### Train coach"))
        #expect(combined.contains("**You:** fill in the weights"))

        let huge = String(repeating: "x", count: LinearFeedbackClient.maxCoachHistoryCharacters + 50)
        let clipped = LinearFeedbackClient.clipCoachHistory(huge)
        #expect(clipped.hasPrefix("…truncated…"))
        #expect(clipped.count <= LinearFeedbackClient.maxCoachHistoryCharacters + 20)
    }
}
