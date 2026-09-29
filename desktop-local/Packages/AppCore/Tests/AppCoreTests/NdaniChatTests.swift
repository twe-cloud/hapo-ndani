import Foundation
import Testing
@testable import AppCore

struct NdaniChatTests {
    @Test
    func chatMessageEncodesAndDecodes() throws {
        let msg = NdaniChatMessage(role: .user, content: "Hello")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(NdaniChatMessage.self, from: data)
        #expect(decoded.id == msg.id)
        #expect(decoded.role == .user)
        #expect(decoded.content == "Hello")
    }

    @Test
    func conversationEncodesAndDecodes() throws {
        var conv = NdaniConversation(title: "Test chat")
        conv.messages.append(NdaniChatMessage(role: .user, content: "Hi"))
        conv.messages.append(NdaniChatMessage(role: .assistant, content: "Hello!"))

        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(NdaniConversation.self, from: data)
        #expect(decoded.title == "Test chat")
        #expect(decoded.messages.count == 2)
        #expect(decoded.messages[0].role == .user)
        #expect(decoded.messages[1].role == .assistant)
    }

    @Test
    func conversationLastMessagePreview() {
        var conv = NdaniConversation()
        #expect(conv.lastMessagePreview == "No messages")

        conv.messages.append(NdaniChatMessage(role: .user, content: "What is privacy?"))
        #expect(conv.lastMessagePreview == "What is privacy?")
    }

    @Test
    func fileAttachmentEncodesAndDecodes() throws {
        let attachment = NdaniFileAttachment(fileName: "test.txt", path: "/tmp/test.txt", characterCount: 42)
        let msg = NdaniChatMessage(role: .user, content: "Read this", fileContext: [attachment])

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(NdaniChatMessage.self, from: data)
        #expect(decoded.fileContext?.count == 1)
        #expect(decoded.fileContext?.first?.fileName == "test.txt")
        #expect(decoded.fileContext?.first?.characterCount == 42)
    }

    @Test
    func conversationStoreSavesAndLoads() throws {
        let conv = NdaniConversation(title: "Persistence test")
        try NdaniConversationStore.save(conv)

        let loaded = NdaniConversationStore.loadAll()
        let found = loaded.first { $0.id == conv.id }
        #expect(found != nil)
        #expect(found?.title == "Persistence test")

        // Cleanup
        NdaniConversationStore.delete(conv.id)
        let afterDelete = NdaniConversationStore.loadAll()
        #expect(afterDelete.first { $0.id == conv.id } == nil)
    }

    @Test
    @MainActor
    func chatStateNewConversation() {
        let chatState = NdaniChatState()
        let initialCount = chatState.conversations.count
        chatState.newConversation()
        #expect(chatState.conversations.count == initialCount + 1)
        #expect(chatState.activeConversationID == chatState.conversations.first?.id)

        // Cleanup persisted file
        if let id = chatState.activeConversationID {
            NdaniConversationStore.delete(id)
        }
    }

    @Test
    @MainActor
    func chatStateDeleteConversation() {
        let chatState = NdaniChatState()
        let initialCount = chatState.conversations.count
        chatState.newConversation()
        #expect(chatState.conversations.count == initialCount + 1)
        let id = chatState.activeConversationID!
        chatState.deleteConversation(id)
        #expect(chatState.conversations.count == initialCount)
    }

    @Test
    @MainActor
    func sendMessageWithoutEngineShowsHelpText() {
        let chatState = NdaniChatState()
        chatState.newConversation()
        chatState.draftMessage = "Explain local privacy"
        chatState.sendMessage()

        let conv = chatState.activeConversation!
        #expect(conv.messages.count == 2) // user + assistant help
        #expect(conv.messages[0].role == .user)
        #expect(conv.messages[1].role == .assistant)
        #expect(conv.messages[1].content.contains("No model loaded"))

        // Cleanup
        NdaniConversationStore.delete(conv.id)
    }

    @Test
    @MainActor
    func firstGreetingShowsNdaniWelcomeWithoutModel() {
        let chatState = NdaniChatState()
        chatState.newConversation()
        chatState.draftMessage = "hiiiii"
        chatState.sendMessage()

        let conv = chatState.activeConversation!
        #expect(conv.messages.count == 2)
        #expect(conv.messages[1].content.contains("Welcome to Hapo Ndani"))
        #expect(conv.messages[1].content.contains("device troubleshooting assistant") == false)

        NdaniConversationStore.delete(conv.id)
    }

    @Test
    @MainActor
    func selfWorkPromptGetsUsefulIntakeWithoutModel() {
        let chatState = NdaniChatState()
        chatState.newConversation()
        chatState.draftMessage = "hiii"
        chatState.sendMessage()
        chatState.draftMessage = "I want to work on me"
        chatState.sendMessage()

        let conv = chatState.activeConversation!
        #expect(conv.messages.count == 4)
        #expect(conv.messages[3].content.contains("We can work on you"))
        #expect(conv.messages[3].content.contains("project") == false)
        #expect(conv.messages[3].content.contains("patience") == false)

        NdaniConversationStore.delete(conv.id)
    }

    @Test
    @MainActor
    func sendMessageIgnoresDuplicateWhileGenerating() {
        let chatState = NdaniChatState()
        chatState.inferenceEngine = HangingInferenceEngine()
        chatState.newConversation()
        chatState.draftMessage = "A concrete non fallback request"
        chatState.sendMessage()
        chatState.draftMessage = "Duplicate"
        chatState.sendMessage()

        let conv = chatState.activeConversation!
        #expect(conv.messages.count == 1)
        #expect(conv.messages[0].content == "A concrete non fallback request")

        chatState.stopGenerating()
        NdaniConversationStore.delete(conv.id)
    }

    @Test
    @MainActor
    func commonIntakePromptsStayNdaniSpecific() {
        let cases = [
            ("I'm overwhelmed", "Start with the pressure"),
            ("help me plan my week", "Give me the messy list"),
            ("what can you do with my files?", "explicitly approve"),
            ("how does memory work?", "keeps memory local"),
            ("draft an email", "Paste the rough version"),
            ("help me ship this product", "trying to ship"),
            ("help me launch this app", "trying to ship"),
            ("Compare two approaches for making this app feel more human", "base model"),
            ("heloo", "Welcome to Hapo Ndani"),
            ("i wannna dance", "I hear you"),
            ("iefjpic", "might not have caught"),
            ("a mi say boom bye bye in a what?", "charged language")
        ]

        for (prompt, expected) in cases {
            let chatState = NdaniChatState()
            chatState.newConversation()
            chatState.draftMessage = prompt
            chatState.sendMessage()

            let conv = chatState.activeConversation!
            #expect(conv.messages.count == 2)
            #expect(conv.messages[1].content.contains(expected))
            #expect(conv.messages[1].content.contains("thanks for your patience") == false)
            #expect(conv.messages[1].content.contains("dead battery") == false)
            #expect(conv.messages[1].content.localizedCaseInsensitiveContains("destination address") == false)
            #expect(conv.messages[1].content.localizedCaseInsensitiveContains("where you'd like it delivered") == false)

            NdaniConversationStore.delete(conv.id)
        }
    }

    @Test
    @MainActor
    func simulatedConversationSetAvoidsGenericSupportPersona() {
        let prompts = [
            "hiii",
            "I want to work on me",
            "I'm overwhelmed",
            "help me plan my week",
            "what can you do with my files?",
            "how does memory work?",
            "draft an email",
            "help me ship this product",
            "help me launch this app",
            "Compare two approaches for making this app feel more human",
            "heloo",
            "i wannna dance",
            "iefjpic",
            "a mi say boom bye bye in a what?"
        ]

        for prompt in prompts {
            let response = NdaniChatState.localFirstResponse(for: prompt)
            #expect(response != nil)
            #expect(response?.contains("Hapo Ndani") == true || response?.isEmpty == false)
            #expect(response?.contains("thanks for your patience") == false)
            #expect(response?.contains("device troubleshooting assistant") == false)
        }
    }

    @Test
    @MainActor
    func troubleshootingPersonaIsSanitized() async throws {
        let chatState = NdaniChatState()
        chatState.inferenceEngine = StaticInferenceEngine(
            response: """
            Hi, thanks for your patience. I'm here to help with your project. Please let me know what you need help with. It's important to understand what you want to work on before we proceed. I'm sorry, but I'm unable to assist with these questions.
            """
        )
        chatState.newConversation()
        chatState.draftMessage = "Explain the private assistant architecture"
        chatState.sendMessage()

        try await waitUntil { !chatState.isGenerating }

        let conv = try #require(chatState.activeConversation)
        #expect(conv.messages.count == 2)
        #expect(conv.messages[1].content.contains("Hapo Ndani"))
        #expect(conv.messages[1].content.contains("device troubleshooting assistant") == false)
        #expect(conv.messages[1].content.contains("thanks for your patience") == false)
        #expect(conv.messages[1].content.contains("unable to assist") == false)
        #expect(conv.messages[1].content.contains("project") == false)

        NdaniConversationStore.delete(conv.id)
    }

    @Test
    @MainActor
    func promptEchoIsSanitized() async throws {
        let prompt = "A concrete phrase the weak model might echo"
        let chatState = NdaniChatState()
        chatState.inferenceEngine = StaticInferenceEngine(response: prompt)
        chatState.newConversation()
        chatState.draftMessage = prompt
        chatState.sendMessage()

        try await waitUntil { !chatState.isGenerating }

        let conv = try #require(chatState.activeConversation)
        #expect(conv.messages.count == 2)
        #expect(conv.messages[1].content != prompt)
        #expect(conv.messages[1].content.contains("little more direction"))

        NdaniConversationStore.delete(conv.id)
    }

    @Test
    @MainActor
    func thinkingTagsAreStrippedBeforeSaving() async throws {
        let chatState = NdaniChatState()
        chatState.inferenceEngine = StaticInferenceEngine(
            response: "<think>I should reason privately.</think>\nTell me what feels most important right now, and we can sort the next step."
        )
        chatState.newConversation()
        chatState.draftMessage = "Compare these two approaches for a private local assistant"
        chatState.sendMessage()

        try await waitUntil { !chatState.isGenerating }

        let conv = try #require(chatState.activeConversation)
        #expect(conv.messages.count == 2)
        #expect(conv.messages[1].content.contains("<think>") == false)
        #expect(conv.messages[1].content.contains("reason privately") == false)
        #expect(conv.messages[1].content.contains("Tell me what feels most important"))

        NdaniConversationStore.delete(conv.id)
    }

    @Test
    @MainActor
    func inferenceStartupFailureKeepsEngineForRetry() async throws {
        let chatState = NdaniChatState()
        let engine = FailingInferenceEngine()
        chatState.inferenceEngine = engine
        chatState.newConversation()
        chatState.draftMessage = "testing 132"
        chatState.sendMessage()

        try await waitUntil { !chatState.isGenerating }

        let conv = try #require(chatState.activeConversation)
        #expect(conv.messages.count == 2)
        #expect(conv.messages[1].role == .assistant)
        #expect(conv.messages[1].content == "Local AI reset itself after a startup issue. Try once more, or reinstall the recommended AI from Home.")
        #expect(conv.messages[1].content.contains("Inference error:") == false)
        #expect(chatState.recoveryMessage == conv.messages[1].content)
        #expect(chatState.inferenceEngine?.modelName == engine.modelName)

        NdaniConversationStore.delete(conv.id)
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = ContinuousClock.now
        while !condition() {
            if start.duration(to: ContinuousClock.now) > timeout {
                Issue.record("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct FailingInferenceEngine: NdaniInferenceEngine {
    var modelName: String { "Failing test model" }
    var isLoaded: Bool { false }

    func generate(messages: [(role: NdaniChatRole, content: String)]) async throws -> AsyncThrowingStream<String, Error> {
        throw TestInferenceError.startup
    }

    func unload() {}
}

private struct StaticInferenceEngine: NdaniInferenceEngine {
    let response: String
    var modelName: String { "Static test model" }
    var isLoaded: Bool { true }

    func generate(messages: [(role: NdaniChatRole, content: String)]) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(response)
            continuation.finish()
        }
    }

    func unload() {}
}

private final class HangingInferenceEngine: @unchecked Sendable, NdaniInferenceEngine {
    var modelName: String { "Hanging test model" }
    var isLoaded: Bool { true }

    func generate(messages: [(role: NdaniChatRole, content: String)]) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { _ in }
    }

    func unload() {}
}

private enum TestInferenceError: Error {
    case startup
}
