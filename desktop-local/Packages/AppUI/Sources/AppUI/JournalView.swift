import AppCore
import SwiftUI

private typealias JournalTheme = NdaniTheme

public struct JournalView: View {
    let journalState: NdaniJournalState
    let desktopState: NdaniDesktopState

    public init(journalState: NdaniJournalState, desktopState: NdaniDesktopState) {
        self.journalState = journalState
        self.desktopState = desktopState
    }

    public var body: some View {
        NavigationSplitView {
            JournalSidebar(journalState: journalState)
        } detail: {
            ZStack {
                JournalTheme.background.ignoresSafeArea()
                if journalState.activeEntry != nil {
                    JournalEntryDetailView(journalState: journalState, desktopState: desktopState)
                } else {
                    JournalEmptyView(journalState: journalState)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            if journalState.activeEntryID == nil {
                journalState.openTodaysEntry()
            }
        }
    }
}

// MARK: - Sidebar

private struct JournalSidebar: View {
    let journalState: NdaniJournalState

    var body: some View {
        VStack(spacing: 0) {
            // Stats bar
            HStack(spacing: 16) {
                StatPill(label: "streak", value: "\(journalState.streak)")
                StatPill(label: "entries", value: "\(journalState.totalEntries)")
                StatPill(label: "words", value: formatWordCount(journalState.totalWords))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(JournalTheme.panel)

            List(selection: Binding(
                get: { journalState.activeEntryID },
                set: { id in
                    if let id { journalState.selectEntry(id) }
                }
            )) {
                ForEach(journalState.entries) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.dateLabel)
                                .font(.headline)
                                .foregroundStyle(JournalTheme.text)
                                .lineLimit(1)
                            Spacer()
                            if !entry.isEmpty {
                                Text("\(entry.wordCount)w")
                                    .font(.caption2)
                                    .foregroundStyle(JournalTheme.muted.opacity(0.75))
                            }
                        }
                        Text(entry.dayOfWeek)
                            .font(.caption)
                            .foregroundStyle(JournalTheme.muted)
                        if !entry.isEmpty {
                            Text(entry.content.prefix(60).description)
                                .font(.caption)
                                .foregroundStyle(JournalTheme.muted.opacity(0.75))
                                .lineLimit(1)
                        } else {
                            Text("Not written yet")
                                .font(.caption)
                                .foregroundStyle(JournalTheme.muted.opacity(0.75))
                                .italic()
                        }
                    }
                    .tag(entry.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            journalState.deleteEntry(entry.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(JournalTheme.background)
            .frame(minWidth: 200)
        }
        .background(JournalTheme.background)
        .toolbar {
            ToolbarItem {
                Button(action: { journalState.openTodaysEntry() }) {
                    Image(systemName: "plus")
                }
                .help("Today's entry")
            }
        }
    }

    private func formatWordCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(JournalTheme.text)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(JournalTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Empty state

private struct JournalEmptyView: View {
    let journalState: NdaniJournalState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(JournalTheme.gold)
                .frame(width: 72, height: 72)
                .background(JournalTheme.gold.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Private Journal")
                .font(.title2.bold())
                .foregroundStyle(JournalTheme.text)
            Text("Write daily. Everything stays on this machine.")
                .foregroundStyle(JournalTheme.muted)
            Button("Start today's entry") {
                journalState.openTodaysEntry()
            }
            .buttonStyle(JournalPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JournalTheme.background)
    }
}

// MARK: - Entry Detail

private struct JournalEntryDetailView: View {
    let journalState: NdaniJournalState
    let desktopState: NdaniDesktopState

    var body: some View {
        VStack(spacing: 0) {
            if let entry = journalState.activeEntry {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.dateLabel)
                            .font(.caption)
                            .foregroundStyle(JournalTheme.muted)
                        Text(entry.dayOfWeek)
                            .font(.caption)
                            .foregroundStyle(JournalTheme.muted.opacity(0.75))
                        Spacer()
                        if !entry.isEmpty {
                            Text("\(entry.wordCount) words")
                                .font(.caption)
                                .foregroundStyle(JournalTheme.muted.opacity(0.75))
                        }
                    }
                    Text(entry.prompt)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(JournalTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .background(JournalTheme.panel)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextEditor(text: Binding(
                        get: { journalState.draftContent },
                        set: {
                            journalState.draftContent = $0
                            journalState.scheduleAutoSave()
                        }
                    ))
                    .font(.body)
                    .foregroundStyle(JournalTheme.text)
                    .lineSpacing(6)
                    .scrollDisabled(true)
                    .frame(minHeight: 200)
                    .padding(12)
                    .scrollContentBackground(.hidden)
                    .background(JournalTheme.panelRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(JournalTheme.border))
                    .accessibilityLabel("Journal entry editor")

                    if let entry = journalState.activeEntry {
                        if journalState.isReflecting {
                            ReflectionStreamingView(
                                text: journalState.streamingReflection,
                                onStop: { journalState.stopReflection() }
                            )
                        } else if let reflection = entry.aiReflection, !reflection.isEmpty {
                            ReflectionView(text: reflection)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(JournalTheme.background)

            JournalBottomBar(journalState: journalState, desktopState: desktopState)
        }
        .background(JournalTheme.background)
    }
}

// MARK: - Reflection Views

private struct ReflectionView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.caption)
                    .foregroundStyle(JournalTheme.mint)
                Text("Reflection")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(JournalTheme.muted)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(JournalTheme.text)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
        .padding(16)
        .background(JournalTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(JournalTheme.border))
    }
}

private struct ReflectionStreamingView: View {
    let text: String
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Reflecting...")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(JournalTheme.muted)
                Spacer()
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.caption)
                        .foregroundStyle(JournalTheme.red)
                }
                .buttonStyle(.plain)
            }
            if !text.isEmpty {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(JournalTheme.text)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .background(JournalTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(JournalTheme.border))
    }
}

// MARK: - Bottom Bar

private struct JournalBottomBar: View {
    let journalState: NdaniJournalState
    let desktopState: NdaniDesktopState

    private var hasContent: Bool {
        !journalState.draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasModel: Bool {
        journalState.inferenceEngine != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            if let saveError = journalState.saveError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(JournalTheme.red)
                Text("Unable to save: \(saveError)")
                    .font(.caption)
                    .foregroundStyle(JournalTheme.red)
                    .lineLimit(1)
                    .accessibilityLabel("Save error: \(saveError)")
            } else if let lastSave = journalState.lastSaveDate {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(JournalTheme.mint.opacity(0.75))
                Text("Saved \(lastSave.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(JournalTheme.muted.opacity(0.75))
                    .accessibilityLabel("Last saved at \(lastSave.formatted(date: .omitted, time: .shortened))")
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(JournalTheme.muted.opacity(0.75))
                Text("Not saved yet")
                    .font(.caption)
                    .foregroundStyle(JournalTheme.muted.opacity(0.75))
            }

            Spacer()

            Button("Save") {
                journalState.saveCurrentDraft()
            }
            .buttonStyle(.bordered)
            .disabled(!hasContent)
            .accessibilityLabel("Save journal entry")

            if hasModel {
                Button(action: { journalState.requestReflection() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                        Text("Reflect")
                    }
                }
                .buttonStyle(JournalPrimaryButtonStyle())
                .disabled(!hasContent || journalState.isReflecting)
            } else {
                Text("Set up private AI from Home for reflections")
                    .font(.caption)
                    .foregroundStyle(JournalTheme.gold)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(JournalTheme.panel)
    }
}

private struct JournalPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(JournalTheme.mint.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
