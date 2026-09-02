import CoachLLM
import Foundation
import Testing
@testable import Persistence

@Suite("Chat store")
struct ChatStoreTests {
    @Test("append and fetch round trip")
    func roundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let user = ChatMessageInsert(
            role: .user,
            text: "Why is readiness low?",
            promptVersion: CoachPromptVersion.chatV1.rawValue
        )
        let assistant = ChatMessageInsert(
            role: .assistant,
            text: "Sleep was short and HRV suppressed.",
            promptVersion: CoachPromptVersion.chatV1.rawValue,
            schemaVersion: CoachOutputSchemaVersion.chatV1.rawValue
        )

        let savedUser = try store.chat.append(user)
        let savedAssistant = try store.chat.append(assistant)
        let loaded = try store.chat.fetchAll()

        #expect(loaded.count == 2)
        #expect(loaded[0].id == savedUser.id)
        #expect(loaded[0].role == .user)
        #expect(loaded[0].text == user.text)
        #expect(loaded[0].promptVersion == CoachPromptVersion.chatV1.rawValue)
        #expect(loaded[0].schemaVersion == nil)
        #expect(loaded[0].sortIndex == 0)

        #expect(loaded[1].id == savedAssistant.id)
        #expect(loaded[1].role == .assistant)
        #expect(loaded[1].schemaVersion == CoachOutputSchemaVersion.chatV1.rawValue)
        #expect(loaded[1].sortIndex == 1)
    }

    @Test("history survives reopening the database pool")
    func relaunchPersistence() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-chat-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let firstStore = try PersistenceStore.open(at: url)
        _ = try firstStore.chat.append(
            ChatMessageInsert(
                role: .user,
                text: "Persist me",
                promptVersion: CoachPromptVersion.chatV1.rawValue
            )
        )

        let reopened = try PersistenceStore.open(at: url)
        let loaded = try reopened.chat.fetchAll()

        #expect(loaded.count == 1)
        #expect(loaded[0].text == "Persist me")
    }

    @Test("clear removes all messages")
    func clearMessages() throws {
        let store = try PersistenceStore.inMemory()
        _ = try store.chat.append(
            ChatMessageInsert(
                role: .user,
                text: "One",
                promptVersion: CoachPromptVersion.chatV1.rawValue
            )
        )
        try store.chat.clear()
        #expect(try store.chat.fetchAll().isEmpty)
    }

    @Test("train surface does not mix into chat fetch or clear")
    func trainSurfaceStaysSeparate() throws {
        let store = try PersistenceStore.inMemory()
        _ = try store.chat.append(
            ChatMessageInsert(
                role: .user,
                text: "Chat only",
                promptVersion: CoachPromptVersion.chatV1.rawValue,
                surface: .chat
            )
        )
        _ = try store.chat.append(
            ChatMessageInsert(
                role: .user,
                text: "Train only",
                promptVersion: CoachPromptVersion.sessionAdjustmentV2.rawValue,
                surface: .train
            )
        )

        let chat = try store.chat.fetchAll(surface: .chat)
        let train = try store.chat.fetchAll(surface: .train)
        #expect(chat.map(\.text) == ["Chat only"])
        #expect(train.map(\.text) == ["Train only"])

        try store.chat.clear(surface: .chat)
        #expect(try store.chat.fetchAll(surface: .chat).isEmpty)
        #expect(try store.chat.fetchAll(surface: .train).map(\.text) == ["Train only"])
    }

    @Test("train append drops oldest rows past the retention window")
    func trainAppendTrimsOldest() throws {
        let store = try PersistenceStore.inMemory()
        for index in 1...5 {
            _ = try store.chat.append(
                ChatMessageInsert(
                    role: .user,
                    text: "t\(index)",
                    promptVersion: CoachPromptVersion.sessionAdjustmentV2.rawValue,
                    surface: .train
                ),
                keepingNewest: 3
            )
        }
        #expect(try store.chat.fetchAll(surface: .train).map(\.text) == ["t3", "t4", "t5"])

        _ = try store.chat.append(
            ChatMessageInsert(
                role: .user,
                text: "chat stays",
                promptVersion: CoachPromptVersion.chatV1.rawValue,
                surface: .chat
            )
        )
        #expect(try store.chat.fetchAll(surface: .chat).map(\.text) == ["chat stays"])
    }
}
