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
        #expect(markdown.contains("**You** _("))
        #expect(markdown.contains("hello"))
        #expect(markdown.contains("**Coach** _("))
        #expect(markdown.contains("hi"))

        _ = try store.chat.append(
            ChatMessageInsert(role: .user, text: "fill in the weights", promptVersion: "session.v2", surface: .train)
        )
        let combined = CoachHistoryExport.markdown(
            chat: try store.chat.fetchAll(surface: .chat),
            train: try store.chat.fetchAll(surface: .train)
        )
        #expect(combined.contains("### Chat"))
        #expect(combined.contains("### Train coach"))
        #expect(combined.contains("fill in the weights"))

        let huge = String(repeating: "x", count: LinearFeedbackClient.maxCoachHistoryCharacters + 50)
        let clipped = LinearFeedbackClient.clipCoachHistory(huge)
        #expect(clipped.hasPrefix("…truncated…"))
        #expect(clipped.count <= LinearFeedbackClient.maxCoachHistoryCharacters + 20)
    }

    @Test("drops messages older than lookback so bugs match submit time")
    func filtersByLookback() throws {
        let store = try PersistenceStore.inMemory()
        let now = Date()
        _ = try store.chat.append(
            ChatMessageInsert(role: .user, text: "old workout chatter", promptVersion: "chat.v1"),
            createdAt: now.addingTimeInterval(-72 * 60 * 60)
        )
        _ = try store.chat.append(
            ChatMessageInsert(role: .user, text: "recent question", promptVersion: "chat.v1"),
            createdAt: now.addingTimeInterval(-30 * 60)
        )
        let markdown = CoachHistoryExport.markdown(
            chat: try store.chat.fetchAll(),
            train: [],
            now: now,
            lookback: 48 * 60 * 60
        )
        #expect(markdown.contains("recent question"))
        #expect(!markdown.contains("old workout chatter"))
        #expect(markdown.contains("Window: last 48h"))
    }
}
