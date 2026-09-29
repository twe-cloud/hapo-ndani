import Foundation
import Testing
@testable import AppCore

struct NdaniJournalTests {
    @Test
    func journalEntryEncodesAndDecodes() throws {
        let entry = NdaniJournalEntry(prompt: "What's on your mind?", content: "Testing things", wordCount: 2)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NdaniJournalEntry.self, from: data)
        #expect(decoded.id == entry.id)
        #expect(decoded.prompt == "What's on your mind?")
        #expect(decoded.content == "Testing things")
        #expect(decoded.wordCount == 2)
    }

    @Test
    func journalEntryIsEmpty() {
        let empty = NdaniJournalEntry(prompt: "Test")
        #expect(empty.isEmpty)

        let whitespace = NdaniJournalEntry(prompt: "Test", content: "   \n  ")
        #expect(whitespace.isEmpty)

        let filled = NdaniJournalEntry(prompt: "Test", content: "Hello world")
        #expect(!filled.isEmpty)
    }

    @Test
    func promptForDateIsDeterministic() {
        let date = Date()
        let prompt1 = NdaniJournalPrompts.promptForDate(date)
        let prompt2 = NdaniJournalPrompts.promptForDate(date)
        #expect(prompt1 == prompt2)
    }

    @Test
    func promptForDateCyclesThroughAllPrompts() {
        var seen = Set<String>()
        let calendar = Calendar.current
        let base = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        for i in 0..<30 {
            let date = calendar.date(byAdding: .day, value: i, to: base)!
            seen.insert(NdaniJournalPrompts.promptForDate(date))
        }
        #expect(seen.count == 30)
    }

    @Test
    func journalStoreSavesAndLoads() throws {
        let entry = NdaniJournalEntry(prompt: "Store test", content: "Persisted", wordCount: 1)
        try NdaniJournalStore.save(entry)

        let loaded = NdaniJournalStore.loadAll()
        let found = loaded.first { $0.id == entry.id }
        #expect(found != nil)
        #expect(found?.content == "Persisted")

        NdaniJournalStore.delete(entry.id)
        let afterDelete = NdaniJournalStore.loadAll()
        #expect(afterDelete.first { $0.id == entry.id } == nil)
    }

    @Test
    func journalStoreHandlesAIReflection() throws {
        var entry = NdaniJournalEntry(prompt: "Reflect test", content: "Some writing", wordCount: 2)
        entry.aiReflection = "Interesting thoughts."
        try NdaniJournalStore.save(entry)

        let loaded = NdaniJournalStore.loadAll()
        let found = loaded.first { $0.id == entry.id }
        #expect(found?.aiReflection == "Interesting thoughts.")

        NdaniJournalStore.delete(entry.id)
    }

    @Test
    @MainActor
    func journalStateOpenTodaysEntry() {
        let state = NdaniJournalState(entries: [])
        state.openTodaysEntry()
        #expect(state.entries.count == 1)
        #expect(state.activeEntryID == state.entries.first?.id)
        #expect(state.activeEntry?.prompt == NdaniJournalPrompts.promptForDate(Date()))

        // Opening again should not create a duplicate
        state.openTodaysEntry()
        #expect(state.entries.count == 1)

        // Cleanup
        if let id = state.activeEntryID {
            NdaniJournalStore.delete(id)
        }
    }

    @Test
    @MainActor
    func journalStateSaveDraft() {
        let state = NdaniJournalState(entries: [])
        state.openTodaysEntry()
        state.draftContent = "Today I worked on the journal feature"
        state.saveCurrentDraft()

        let entry = state.activeEntry!
        #expect(entry.content == "Today I worked on the journal feature")
        #expect(entry.wordCount == 7)

        // Cleanup
        NdaniJournalStore.delete(entry.id)
    }

    @Test
    @MainActor
    func journalStateDeleteEntry() {
        let state = NdaniJournalState(entries: [])
        state.openTodaysEntry()
        let id = state.activeEntryID!
        state.deleteEntry(id)
        #expect(state.entries.isEmpty)
        #expect(state.activeEntryID == nil)
    }

    @Test
    @MainActor
    func journalStateStreak() {
        let calendar = Calendar.current
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        let entries = [
            NdaniJournalEntry(prompt: "P1", content: "Day 1", createdAt: today, wordCount: 2),
            NdaniJournalEntry(prompt: "P2", content: "Day 2", createdAt: yesterday, wordCount: 2),
            NdaniJournalEntry(prompt: "P3", content: "Day 3", createdAt: twoDaysAgo, wordCount: 2),
        ]

        let state = NdaniJournalState(entries: entries)
        #expect(state.streak == 3)

        // Cleanup
        for entry in entries {
            NdaniJournalStore.delete(entry.id)
        }
    }

    @Test
    @MainActor
    func journalStateStreakBreaksOnGap() {
        let calendar = Calendar.current
        let today = Date()
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!

        let entries = [
            NdaniJournalEntry(prompt: "P1", content: "Today", createdAt: today, wordCount: 1),
            NdaniJournalEntry(prompt: "P2", content: "Old", createdAt: threeDaysAgo, wordCount: 1),
        ]

        let state = NdaniJournalState(entries: entries)
        #expect(state.streak == 1)
    }

    @Test
    @MainActor
    func journalStateTotalWords() {
        let entries = [
            NdaniJournalEntry(prompt: "P1", content: "One", wordCount: 1),
            NdaniJournalEntry(prompt: "P2", content: "Two words", wordCount: 2),
            NdaniJournalEntry(prompt: "P3", content: "Three more words", wordCount: 3),
        ]
        let state = NdaniJournalState(entries: entries)
        #expect(state.totalWords == 6)
        #expect(state.totalEntries == 3)
    }

    @Test
    @MainActor
    func journalStateEmptyEntriesNotCounted() {
        let entries = [
            NdaniJournalEntry(prompt: "P1", content: "Written", wordCount: 1),
            NdaniJournalEntry(prompt: "P2", content: "", wordCount: 0),
        ]
        let state = NdaniJournalState(entries: entries)
        #expect(state.totalEntries == 1)
    }
}
