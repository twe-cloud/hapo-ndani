import Foundation
import Observation
import os

private let logger = Logger(subsystem: "biz.nibiashara.ndani", category: "Memory")
private let memoryQueue = DispatchQueue(label: "biz.nibiashara.ndani.memoryStore")

// MARK: - Memory Store

public enum NdaniMemoryStore {
    private static func memoryFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Ndani", isDirectory: true)
            .appendingPathComponent("memories.md")
    }

    public static func load() -> String {
        guard let url = memoryFileURL(),
              let text = NdaniPrivateFileStore.readPrivateStringMigrating(from: url)
        else { return "" }
        return text
    }

    public static func save(_ content: String) {
        guard let url = memoryFileURL() else { return }
        do {
            try NdaniPrivateFileStore.writePrivateStringThrowing(content, to: url)
        } catch {
            logger.error("Failed to save memory: \(error.localizedDescription)")
        }
    }

    /// Thread-safe append using a serial queue to prevent read-modify-write races
    public static func append(_ line: String) {
        memoryQueue.sync {
            var current = load()
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { return }

            let existingLines = Set(current.components(separatedBy: .newlines).map {
                var l = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if l.hasPrefix("- ") { l = String(l.dropFirst(2)) }
                return l
            })
            if existingLines.contains(trimmedLine.lowercased()) { return }

            if !current.isEmpty && !current.hasSuffix("\n") {
                current += "\n"
            }
            current += "- \(trimmedLine)\n"

            let lines = current.components(separatedBy: .newlines)
            if lines.count > 55 {
                let kept = lines.suffix(50).joined(separator: "\n")
                save(kept)
            } else {
                save(current)
            }
        }
    }
}

// MARK: - Memory State

@MainActor
@Observable
public final class NdaniMemoryState {
    public var content: String
    public var isExtracting: Bool = false
    private var extractionTask: Task<Void, Never>?

    public init() {
        self.content = NdaniMemoryStore.load()
    }

    // For testing
    public init(content: String) {
        self.content = content
    }

    public func reload() {
        content = NdaniMemoryStore.load()
    }

    public func save() {
        NdaniMemoryStore.save(content)
    }

    public func clear() {
        content = ""
        NdaniMemoryStore.save("")
    }

    public var isEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var lineCount: Int {
        guard !isEmpty else { return 0 }
        return content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    /// Builds a system prompt fragment with the user's memories.
    public var systemPromptFragment: String? {
        guard !isEmpty else { return nil }
        return """
        You have memories about this user from previous sessions. \
        Use these naturally — reference them when relevant, don't recite them. \
        If something contradicts a memory, trust the current conversation.\n\n\(content)
        """
    }

    /// Extracts a memory from a journal entry + reflection using the local model.
    public func extractMemory(
        journalContent: String,
        journalPrompt: String,
        reflection: String?,
        engine: NdaniInferenceEngine
    ) {
        extractionTask?.cancel()
        isExtracting = true

        let messages: [(role: NdaniChatRole, content: String)] = [
            (.system, """
            You are a memory extractor. The user wrote a journal entry. \
            Extract 0-2 short facts about the user worth remembering for future conversations. \
            Facts should be about their interests, preferences, habits, goals, background, or personality. \
            Output ONLY the facts as plain bullet points starting with "- ". \
            If there is nothing worth remembering, output exactly: NONE \
            Do not explain. Do not add commentary. Do not repeat the entry.
            """),
            (.user, """
            Prompt: \(journalPrompt)
            Entry: \(journalContent)
            \(reflection.map { "Reflection: \($0)" } ?? "")
            """),
        ]

        extractionTask = Task { [weak self] in
            var result = ""
            do {
                let stream = try await engine.generate(messages: messages)
                for try await token in stream {
                    guard !Task.isCancelled else { break }
                    result += token
                }
            } catch {
                // Silently fail — memory extraction is optional
            }

            await MainActor.run {
                guard let self else { return }
                self.isExtracting = false

                let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.uppercased() != "NONE" else { return }

                // Parse bullet points and append each
                let lines = trimmed.components(separatedBy: .newlines)
                for line in lines {
                    var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.hasPrefix("- ") {
                        cleaned = String(cleaned.dropFirst(2))
                    }
                    guard !cleaned.isEmpty, cleaned.uppercased() != "NONE" else { continue }
                    NdaniMemoryStore.append(cleaned)
                }
                self.reload()
            }
        }
    }
}
