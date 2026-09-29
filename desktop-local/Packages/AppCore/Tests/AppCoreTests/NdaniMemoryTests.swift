import Foundation
import Testing
@testable import AppCore

// File-based store tests must run serially since they share ~/Library/Application Support/Ndani/memories.md
@Suite(.serialized)
struct NdaniMemoryStoreTests {
    @Test
    func memoryStoreSavesAndLoads() {
        let original = NdaniMemoryStore.load()
        defer { NdaniMemoryStore.save(original) }

        NdaniMemoryStore.save("- Likes coffee\n- Works in Dallas\n")
        let loaded = NdaniMemoryStore.load()
        #expect(loaded.contains("Likes coffee"))
        #expect(loaded.contains("Works in Dallas"))
    }

    @Test
    func memoryStoreAppendPreventsDuplicates() {
        let original = NdaniMemoryStore.load()
        defer { NdaniMemoryStore.save(original) }

        NdaniMemoryStore.save("")
        NdaniMemoryStore.append("Enjoys running")
        NdaniMemoryStore.append("Enjoys running")
        let loaded = NdaniMemoryStore.load()
        let occurrences = loaded.components(separatedBy: "Enjoys running").count - 1
        #expect(occurrences == 1)
    }

    @Test
    func memoryStoreAppendSkipsEmpty() {
        let original = NdaniMemoryStore.load()
        defer { NdaniMemoryStore.save(original) }

        NdaniMemoryStore.save("- Existing\n")
        NdaniMemoryStore.append("")
        NdaniMemoryStore.append("   ")
        let loaded = NdaniMemoryStore.load()
        #expect(loaded.trimmingCharacters(in: .whitespacesAndNewlines) == "- Existing")
    }
}

struct NdaniMemoryStateTests {
    @Test
    @MainActor
    func memoryStateLineCount() {
        let state = NdaniMemoryState(content: "- One\n- Two\n- Three\n")
        #expect(state.lineCount == 3)
    }

    @Test
    @MainActor
    func memoryStateEmptyCheck() {
        let empty = NdaniMemoryState(content: "")
        #expect(empty.isEmpty)

        let whitespace = NdaniMemoryState(content: "  \n  ")
        #expect(whitespace.isEmpty)

        let filled = NdaniMemoryState(content: "- A fact")
        #expect(!filled.isEmpty)
    }

    @Test
    @MainActor
    func memoryStateSystemPromptFragment() {
        let empty = NdaniMemoryState(content: "")
        #expect(empty.systemPromptFragment == nil)

        let filled = NdaniMemoryState(content: "- Likes Swift\n- Based in Texas\n")
        let fragment = filled.systemPromptFragment
        #expect(fragment != nil)
        #expect(fragment!.contains("Likes Swift"))
        #expect(fragment!.contains("Based in Texas"))
        #expect(fragment!.contains("memories about this user"))
    }

    @Test
    @MainActor
    func memoryStateClear() {
        let state = NdaniMemoryState(content: "- Some memory\n")
        state.clear()
        #expect(state.isEmpty)
        #expect(state.lineCount == 0)
    }
}
