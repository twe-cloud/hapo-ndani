import AppCore
import SwiftUI

private typealias ChatTheme = NdaniTheme

public struct ChatView: View {
    let chatState: NdaniChatState
    let desktopState: NdaniDesktopState

    public init(chatState: NdaniChatState, desktopState: NdaniDesktopState) {
        self.chatState = chatState
        self.desktopState = desktopState
    }

    public var body: some View {
        NavigationSplitView {
            ConversationSidebar(chatState: chatState)
                .accessibilityLabel("Conversation list")
        } detail: {
            ZStack {
                ChatTheme.background.ignoresSafeArea()
                if chatState.activeConversation != nil {
                    ConversationDetailView(chatState: chatState, desktopState: desktopState)
                } else {
                    EmptyConversationView(chatState: chatState, desktopState: desktopState)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - Sidebar

private struct ConversationSidebar: View {
    let chatState: NdaniChatState

    var body: some View {
        List(selection: Binding(
            get: { chatState.activeConversationID },
            set: { id in
                if let id { chatState.selectConversation(id) }
            }
        )) {
            ForEach(chatState.conversations) { conv in
                VStack(alignment: .leading, spacing: 2) {
                    Text(conv.title)
                        .font(.headline)
                        .foregroundStyle(ChatTheme.text)
                        .lineLimit(1)
                    Text(conv.lastMessagePreview)
                        .font(.caption)
                        .foregroundStyle(ChatTheme.muted)
                        .lineLimit(1)
                    Text(conv.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(ChatTheme.muted.opacity(0.75))
                }
                .tag(conv.id)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        chatState.deleteConversation(conv.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(ChatTheme.background)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem {
                Button(action: { chatState.newConversation() }) {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

// MARK: - Empty state

private struct EmptyConversationView: View {
    let chatState: NdaniChatState
    let desktopState: NdaniDesktopState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(ChatTheme.gold)
                .frame(width: 72, height: 72)
                .background(ChatTheme.gold.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Start a conversation")
                .font(.title2.bold())
                .foregroundStyle(ChatTheme.text)
            Text("Your prompts and responses stay on this machine.")
                .foregroundStyle(ChatTheme.muted)

            if desktopState.launchableModelCount == 0 {
                Text("Set up private AI from Home first.")
                    .font(.callout)
                    .foregroundStyle(ChatTheme.gold)
            }

            if chatState.hasFolderContext {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(ChatTheme.mint)
                    Text("Your approved folders are available as context.")
                        .font(.callout)
                        .foregroundStyle(ChatTheme.muted)
                }
                .padding(.top, 4)
            } else {
                Text("Allow a folder from Home when you want help with files.")
                    .font(.callout)
                    .foregroundStyle(ChatTheme.muted)
            }

            Button("New conversation") {
                chatState.newConversation()
            }
            .buttonStyle(ChatPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChatTheme.background)
    }
}

// MARK: - Conversation Detail

private struct ConversationDetailView: View {
    let chatState: NdaniChatState
    let desktopState: NdaniDesktopState
    @State private var isFileDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if let saveError = chatState.saveError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("Unable to save: \(saveError)")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button("Dismiss") { chatState.saveError = nil }
                        .font(.caption)
                        .buttonStyle(.plain)
                }
                .foregroundStyle(ChatTheme.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(ChatTheme.red.opacity(0.1))
                .accessibilityLabel("Save error: \(saveError)")
            }

            HStack(spacing: 6) {
                if let engine = chatState.inferenceEngine {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(ChatTheme.mint)
                    Text("Private AI ready")
                        .font(.caption)
                        .foregroundStyle(ChatTheme.muted)
                    Text(engine.modelName.contains("14B") ? "Large" : "Local")
                        .font(.caption)
                        .foregroundStyle(ChatTheme.mint)
                } else {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(ChatTheme.gold)
                    Text("Set up private AI from Home")
                        .font(.caption)
                        .foregroundStyle(ChatTheme.gold)
                }
                Spacer()
                if chatState.hasFolderContext {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8))
                        Text("Files")
                            .font(.caption)
                    }
                    .foregroundStyle(ChatTheme.mint)
                    .help("Your approved folders are included as context")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(ChatTheme.panel)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let conv = chatState.activeConversation {
                            ForEach(conv.messages) { message in
                                ChatMessageView(message: message)
                                    .id(message.id)
                            }
                        }

                        // Streaming response
                        if chatState.isGenerating && !chatState.streamingResponse.isEmpty {
                            StreamingMessageView(text: chatState.streamingResponse)
                                .id("streaming")
                        }

                        if chatState.isGenerating && chatState.streamingResponse.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .foregroundStyle(ChatTheme.muted)
                            }
                            .padding(.horizontal, 16)
                            .id("thinking")
                        }
                    }
                    .padding(.vertical, 16)
                }
                .background(ChatTheme.background)
                .onChange(of: chatState.activeConversation?.messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: chatState.streamingResponse) {
                    scrollToBottom(proxy: proxy)
                }
            }

            if !chatState.droppedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chatState.droppedFiles) { file in
                            FileChip(fileName: file.fileName, charCount: file.characterCount) {
                                chatState.droppedFiles.removeAll { $0.id == file.id }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .background(ChatTheme.panel)
            }

            ChatInputArea(chatState: chatState, desktopState: desktopState)
        }
        .background(ChatTheme.background)
        .overlay {
            if isFileDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(ChatTheme.mint, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .background(ChatTheme.mint.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isFileDropTargeted) { providers in
            handleFileDrop(providers)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if chatState.isGenerating {
            proxy.scrollTo("streaming", anchor: .bottom)
        } else if let lastID = chatState.activeConversation?.messages.last?.id {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    chatState.addDroppedFile(url: url)
                }
            }
        }
        return true
    }
}

// MARK: - Message Views

private struct ChatMessageView: View {
    let message: NdaniChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if let files = message.fileContext, !files.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.caption)
                        Text("\(files.count) file\(files.count == 1 ? "" : "s") attached")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                Text(message.content)
                    .textSelection(.enabled)
                    .padding(12)
                    .foregroundStyle(ChatTheme.text)
                    .background(message.role == .user ? ChatTheme.mint.opacity(0.18) : ChatTheme.panelRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ChatTheme.border))

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(ChatTheme.muted.opacity(0.7))
            }

            if message.role == .assistant || message.role == .system {
                Spacer(minLength: 80)
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "You" : "Hapo Ndani"): \(message.content)")
    }
}

private struct StreamingMessageView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .textSelection(.enabled)
                    .padding(12)
                    .foregroundStyle(ChatTheme.text)
                    .background(ChatTheme.panelRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ChatTheme.border))
            }
            Spacer(minLength: 80)
        }
        .padding(.horizontal, 16)
    }
}

private struct FileChip: View {
    let fileName: String
    let charCount: Int
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.caption)
            Text(fileName)
                .font(.caption)
                .lineLimit(1)
            Text("(\(charCount) chars)")
                .font(.caption2)
                .foregroundStyle(ChatTheme.muted)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(ChatTheme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ChatTheme.panelRaised)
        .clipShape(Capsule())
    }
}

// MARK: - Input Area

private struct ChatInputArea: View {
    let chatState: NdaniChatState
    let desktopState: NdaniDesktopState

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message Hapo Ndani...", text: Binding(
                get: { chatState.draftMessage },
                set: { chatState.draftMessage = $0 }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...8)
            .padding(10)
            .foregroundStyle(ChatTheme.text)
            .background(ChatTheme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ChatTheme.border))
            .onSubmit {
                if !chatState.isGenerating {
                    chatState.sendMessage()
                }
            }

            if chatState.isGenerating {
                Button(action: { chatState.stopGenerating() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(ChatTheme.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop generating")
            } else {
                Button(action: { chatState.sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(chatState.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? ChatTheme.muted
                            : ChatTheme.mint)
                }
                .buttonStyle(.plain)
                .disabled(chatState.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send message")
            }
        }
        .padding(12)
        .background(ChatTheme.panel)
    }
}

private struct ChatPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(ChatTheme.mint.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
