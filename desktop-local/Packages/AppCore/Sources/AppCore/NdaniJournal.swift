import Foundation
import Observation
import os

private let logger = Logger(subsystem: "biz.nibiashara.ndani", category: "Journal")

// MARK: - Journal Entry

public struct NdaniJournalEntry: Identifiable, Codable, Sendable {
    public let id: UUID
    public var prompt: String
    public var content: String
    public var aiReflection: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var wordCount: Int

    public init(
        id: UUID = UUID(),
        prompt: String,
        content: String = "",
        aiReflection: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        wordCount: Int = 0
    ) {
        self.id = id
        self.prompt = prompt
        self.content = content
        self.aiReflection = aiReflection
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.wordCount = wordCount
    }

    public var dateLabel: String {
        createdAt.formatted(date: .abbreviated, time: .omitted)
    }

    public var dayOfWeek: String {
        createdAt.formatted(.dateTime.weekday(.wide))
    }

    public var isEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Writing Prompts

public enum NdaniJournalPrompts {
    public static let prompts: [String] = [
        "What's on your mind right now?",
        "Describe something you noticed today that you usually overlook.",
        "What's a decision you're currently weighing?",
        "Write about a skill you're building and why it matters to you.",
        "What does your ideal ordinary day look like?",
        "Describe a recent conversation that stuck with you.",
        "What are you avoiding, and why?",
        "Write about someone whose work you admire — what specifically draws you?",
        "What would you do differently if no one was watching?",
        "Describe a place that feels like home, even if it isn't.",
        "What's something you changed your mind about recently?",
        "Write about how you spend the first hour of your day.",
        "What's a question you keep returning to?",
        "Describe a problem you solved recently and how you approached it.",
        "What does privacy mean to you in practice, not in theory?",
        "Write about a mistake that taught you something useful.",
        "What are you most curious about right now?",
        "Describe your relationship with technology — honest version.",
        "What would you build if you had unlimited time?",
        "Write about a tradition or habit that defines you.",
        "What's the best advice you've ignored?",
        "Describe what you're working on and why it matters.",
        "What's something you do well that others find difficult?",
        "Write about a moment of unexpected kindness.",
        "What does success look like for you this week?",
        "Describe how you make decisions under uncertainty.",
        "What's a belief you hold that most people around you don't share?",
        "Write about what you're reading, watching, or listening to.",
        "What would you tell your past self from one year ago?",
        "Describe something you're proud of that no one else knows about.",
    ]

    public static func promptForDate(_ date: Date) -> String {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return prompts[(dayOfYear - 1) % prompts.count]
    }
}

// MARK: - Journal Store (file-based)

public enum NdaniJournalStore {
    private static func storeDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Ndani", isDirectory: true)
            .appendingPathComponent("journal", isDirectory: true)
    }

    public enum StoreError: LocalizedError {
        case noStoreDirectory
        case encodingFailed
        case writeFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .noStoreDirectory: "Could not access journal storage directory."
            case .encodingFailed: "Could not encode journal entry."
            case .writeFailed(let error): "Could not save journal entry: \(error.localizedDescription)"
            }
        }
    }

    public static func save(_ entry: NdaniJournalEntry) throws {
        guard let dir = storeDirectory() else { throw StoreError.noStoreDirectory }
        let file = dir.appendingPathComponent("\(entry.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entry) else { throw StoreError.encodingFailed }
        do {
            try NdaniPrivateFileStore.writePrivateDataThrowing(data, to: file)
        } catch {
            throw StoreError.writeFailed(error)
        }
    }

    public static func loadAll() -> [NdaniJournalEntry] {
        guard let dir = storeDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: dir,
                  includingPropertiesForKeys: nil,
                  options: .skipsHiddenFiles
              )
        else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> NdaniJournalEntry? in
                guard let data = NdaniPrivateFileStore.readPrivateDataMigrating(from: url) else { return nil }
                return try? decoder.decode(NdaniJournalEntry.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public static func delete(_ id: UUID) {
        guard let dir = storeDirectory() else { return }
        let file = dir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
    }
}

// MARK: - Journal State

@MainActor
@Observable
public final class NdaniJournalState {
    public var entries: [NdaniJournalEntry]
    public var activeEntryID: UUID?
    public var draftContent: String = ""
    public var isReflecting: Bool = false
    public var streamingReflection: String = ""
    public var recoveryMessage: String?
    public var saveError: String?
    public var lastSaveDate: Date?

    private var reflectionTask: Task<Void, Never>?
    private var autoSaveTask: Task<Void, Never>?
    public var inferenceEngine: NdaniInferenceEngine?
    public var memoryState: NdaniMemoryState?

    public var activeEntry: NdaniJournalEntry? {
        guard let id = activeEntryID else { return nil }
        return entries.first { $0.id == id }
    }

    public var todaysEntry: NdaniJournalEntry? {
        let calendar = Calendar.current
        return entries.first { calendar.isDateInToday($0.createdAt) }
    }

    public var streak: Int {
        guard !entries.isEmpty else { return 0 }
        let calendar = Calendar.current
        let sortedDates = Set(entries.filter { !$0.isEmpty }.map {
            calendar.startOfDay(for: $0.createdAt)
        }).sorted(by: >)

        guard let latest = sortedDates.first else { return 0 }
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        guard latest >= yesterday else { return 0 }

        var count = 1
        for i in 1..<sortedDates.count {
            guard let expected = calendar.date(byAdding: .day, value: -i, to: latest) else { break }
            if calendar.isDate(sortedDates[i], inSameDayAs: expected) {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    public var totalEntries: Int {
        entries.filter { !$0.isEmpty }.count
    }

    public var totalWords: Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }

    public init() {
        self.entries = NdaniJournalStore.loadAll()
    }

    // For testing
    public init(entries: [NdaniJournalEntry]) {
        self.entries = entries
    }

    public func openTodaysEntry() {
        if let existing = todaysEntry {
            activeEntryID = existing.id
            draftContent = existing.content
        } else {
            let prompt = NdaniJournalPrompts.promptForDate(Date())
            let entry = NdaniJournalEntry(prompt: prompt)
            entries.insert(entry, at: 0)
            activeEntryID = entry.id
            draftContent = ""
            trySave(entry)
        }
    }

    public func selectEntry(_ id: UUID) {
        // Save current draft before switching
        saveCurrentDraft()
        activeEntryID = id
        if let entry = activeEntry {
            draftContent = entry.content
        }
    }

    public func saveCurrentDraft() {
        guard let idx = entries.firstIndex(where: { $0.id == activeEntryID }) else { return }
        let trimmed = draftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[idx].content = draftContent
        entries[idx].wordCount = trimmed.split(separator: " ").count
        entries[idx].updatedAt = Date()
        trySave(entries[idx])
    }

    /// Schedule an auto-save after a 2-second debounce
    public func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.saveCurrentDraft()
            }
        }
    }

    private func trySave(_ entry: NdaniJournalEntry) {
        do {
            try NdaniJournalStore.save(entry)
            saveError = nil
            lastSaveDate = Date()
        } catch {
            logger.error("Failed to save journal entry: \(error.localizedDescription)")
            saveError = error.localizedDescription
        }
    }

    public func deleteEntry(_ id: UUID) {
        entries.removeAll { $0.id == id }
        if activeEntryID == id {
            activeEntryID = entries.first?.id
            if let entry = activeEntry {
                draftContent = entry.content
            } else {
                draftContent = ""
            }
        }
        NdaniJournalStore.delete(id)
    }

    public func requestReflection() {
        saveCurrentDraft()
        guard let entry = activeEntry, !entry.isEmpty else { return }
        guard let engine = inferenceEngine else { return }

        isReflecting = true
        streamingReflection = ""
        recoveryMessage = nil

        var messages: [(role: NdaniChatRole, content: String)] = [
            (.system, """
            You are a thoughtful, private journal companion running locally on the user's device. \
            The user wrote a journal entry in response to a prompt. Offer a brief, genuine reflection — \
            notice something in what they wrote, ask a follow-up question, or gently connect it to a broader idea. \
            Keep it under 150 words. Be warm but not performative. Never summarize what they already said. \
            Never use phrases like "I appreciate you sharing" or "That's a great point."
            """),
        ]

        if let memoryFragment = memoryState?.systemPromptFragment {
            messages.append((.system, memoryFragment))
        }

        messages.append((.user, "Prompt: \(entry.prompt)\n\nMy entry:\n\(entry.content)"))

        reflectionTask = Task { [weak self] in
            do {
                let stream = try await engine.generate(messages: messages)
                for try await token in stream {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        self?.streamingReflection += token
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self?.inferenceEngine = nil
                        if self?.streamingReflection.isEmpty == true {
                            let message = "Local AI reset itself after a startup issue. Your journal entry stayed saved."
                            self?.streamingReflection = message
                            self?.recoveryMessage = message
                        }
                    }
                }
            }

            await MainActor.run {
                guard let self else { return }
                let reflection = self.streamingReflection
                if !reflection.isEmpty,
                   let idx = self.entries.firstIndex(where: { $0.id == self.activeEntryID }) {
                    self.entries[idx].aiReflection = reflection
                    self.entries[idx].updatedAt = Date()
                    self.trySave(self.entries[idx])

                    // Extract memories from this journal entry
                    if let memoryState = self.memoryState, let engine = self.inferenceEngine {
                        memoryState.extractMemory(
                            journalContent: self.entries[idx].content,
                            journalPrompt: self.entries[idx].prompt,
                            reflection: reflection,
                            engine: engine
                        )
                    }
                }
                self.streamingReflection = ""
                self.isReflecting = false
                self.reflectionTask = nil
            }
        }
    }

    public func stopReflection() {
        reflectionTask?.cancel()
        reflectionTask = nil
        isReflecting = false

        if !streamingReflection.isEmpty,
           let idx = entries.firstIndex(where: { $0.id == activeEntryID }) {
            entries[idx].aiReflection = streamingReflection
            entries[idx].updatedAt = Date()
            trySave(entries[idx])
        }
        streamingReflection = ""
    }
}
