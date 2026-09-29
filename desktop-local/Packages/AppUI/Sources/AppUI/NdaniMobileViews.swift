import AppCore
import SwiftUI

public struct NdaniMobileRootView: View {
    @State private var journalState = NdaniJournalState()
    @State private var chatState = NdaniChatState()
    @State private var memoryState = NdaniMemoryState()
    @State private var desktopState = NdaniDesktopState()
    @State private var selectedTab: MobileTab = .home
    @State private var recoveryNotice: MobileRecoveryNotice?
    @Environment(\.scenePhase) private var scenePhase

    private let capability: NdaniPlatformCapability
    private let inferenceEngineFactory: ((NdaniLocalModelStatus) -> NdaniInferenceEngine?)?

    public init(
        capability: NdaniPlatformCapability = .current(),
        inferenceEngineFactory: ((NdaniLocalModelStatus) -> NdaniInferenceEngine?)? = nil
    ) {
        self.capability = capability
        self.inferenceEngineFactory = inferenceEngineFactory
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            NdaniMobileDashboardView(
                capability: capability,
                memoryState: memoryState,
                desktopState: desktopState
            )
                .tabItem { Label("Home", systemImage: "house") }
                .tag(MobileTab.home)

            NdaniMobileChatView(
                chatState: chatState,
                desktopState: desktopState,
                capability: capability
            )
                .tabItem { Label("Chat", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(MobileTab.chat)

            NdaniMobileJournalView(
                journalState: journalState,
                desktopState: desktopState,
                capability: capability
            )
                .tabItem { Label("Journal", systemImage: "book.closed") }
                .tag(MobileTab.journal)
        }
        .tint(NdaniMobileTheme.accent)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .top) {
            if let recoveryNotice {
                MobileRecoveryBanner(
                    notice: recoveryNotice,
                    retry: { retryRecovery(recoveryNotice) },
                    dismiss: { self.recoveryNotice = nil }
                )
            }
        }
        .onAppear {
            if let tier = capability.mode.recommendedTier {
                desktopState.selectedTier = tier
            }
            desktopState.refreshModelStatuses()
            connectInferenceEngine()
            journalState.memoryState = memoryState
            chatState.memoryProvider = { memoryState.systemPromptFragment }
            syncRecoveryNotice()
        }
        .onChange(of: desktopState.modelStatuses) {
            connectInferenceEngine()
            syncRecoveryNotice()
        }
        .onChange(of: chatState.recoveryMessage) {
            syncRecoveryNotice()
        }
        .onChange(of: journalState.recoveryMessage) {
            syncRecoveryNotice()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                journalState.saveCurrentDraft()
            }
        }
    }

    private func connectInferenceEngine() {
        guard let inferenceEngineFactory,
              let readyModel = desktopState.preferredLaunchableModelStatus(physicalMemoryBytes: capability.physicalMemoryBytes),
              chatState.inferenceEngine?.modelName != readyModel.package.title,
              let engine = inferenceEngineFactory(readyModel)
        else {
            return
        }

        chatState.inferenceEngine = engine
        journalState.inferenceEngine = engine
    }

    private func syncRecoveryNotice() {
        if let package = desktopState.recommendedPackage(for: capability),
           case .failed(let message) = desktopState.modelDownloader.statuses[package.id] {
            setRecoveryNotice(
                MobileRecoveryNotice(
                    source: .modelSetup,
                    title: "Setup needs another try",
                    message: message,
                    actionTitle: "Retry"
                )
            )
            return
        }

        if let message = chatState.recoveryMessage {
            setRecoveryNotice(
                MobileRecoveryNotice(
                    source: .chatRuntime,
                    title: "Local AI recovered",
                    message: message,
                    actionTitle: "Reconnect"
                )
            )
            return
        }

        if let message = journalState.recoveryMessage {
            setRecoveryNotice(
                MobileRecoveryNotice(
                    source: .journalRuntime,
                    title: "Journal stayed saved",
                    message: message,
                    actionTitle: "Reconnect"
                )
            )
        }
    }

    private func setRecoveryNotice(_ notice: MobileRecoveryNotice) {
        guard recoveryNotice != notice else { return }
        recoveryNotice = notice
    }

    private func retryRecovery(_ notice: MobileRecoveryNotice) {
        switch notice.source {
        case .modelSetup:
            if let package = desktopState.recommendedPackage(for: capability) {
                desktopState.downloadModel(package)
            }
        case .chatRuntime, .journalRuntime:
            chatState.recoveryMessage = nil
            journalState.recoveryMessage = nil
            desktopState.refreshModelStatuses()
            connectInferenceEngine()
        }
        recoveryNotice = nil
    }
}

private enum MobileTab: String {
    case home
    case chat
    case journal
}

private enum NdaniMobileTheme {
    static let background = Color(red: 0.045, green: 0.055, blue: 0.052)
    static let panel = Color(red: 0.085, green: 0.1, blue: 0.095)
    static let panelStrong = Color(red: 0.12, green: 0.14, blue: 0.13)
    static let accent = Color(red: 0.36, green: 0.86, blue: 0.68)
    static let accentMuted = Color(red: 0.12, green: 0.28, blue: 0.23)
    static let border = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.68)
}

private enum MobileRecoverySource: Equatable {
    case modelSetup
    case chatRuntime
    case journalRuntime
}

private struct MobileRecoveryNotice: Equatable {
    let source: MobileRecoverySource
    let title: String
    let message: String
    let actionTitle: String
}

private struct MobileRecoveryBanner: View {
    let notice: MobileRecoveryNotice
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill")
                .foregroundStyle(Color(red: 0, green: 0.55, blue: 0.45))
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(.caption.weight(.semibold))
                Text(notice.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(notice.actionTitle, action: retry)
                .font(.caption.weight(.semibold))

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss recovery message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NdaniMobileTheme.panel)
        .accessibilityIdentifier("mobileRecoveryBanner")
    }
}

public struct NdaniMobileJournalView: View {
    private let journalState: NdaniJournalState
    private let desktopState: NdaniDesktopState
    private let capability: NdaniPlatformCapability

    public init(
        journalState: NdaniJournalState,
        desktopState: NdaniDesktopState,
        capability: NdaniPlatformCapability
    ) {
        self.journalState = journalState
        self.desktopState = desktopState
        self.capability = capability
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let entry = journalState.activeEntry {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(entry.dateLabel)
                                    Text(entry.dayOfWeek)
                                    Spacer()
                                    Text("\(entry.wordCount) words")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Text(entry.prompt)
                                    .font(.title2.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("mobileJournalPrompt")
                            }
                        }

                        TextEditor(text: Binding(
                            get: { journalState.draftContent },
                            set: {
                                journalState.draftContent = $0
                                journalState.scheduleAutoSave()
                            }
                        ))
                        .font(.body)
                        .lineSpacing(5)
                        .frame(minHeight: 360)
                        .padding(10)
                        #if os(iOS)
                        .scrollContentBackground(.hidden)
                        #endif
                        .background(NdaniMobileTheme.panelStrong)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(NdaniMobileTheme.border)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("mobileJournalEditor")

                        if let entry = journalState.activeEntry,
                           let reflection = entry.aiReflection,
                           !reflection.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Reflection", systemImage: "sparkle")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text(reflection)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(NdaniMobileTheme.accentMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                MobileJournalBottomBar(
                    journalState: journalState,
                    desktopState: desktopState,
                    capability: capability
                )
            }
            .background(NdaniMobileTheme.background.ignoresSafeArea())
            .navigationTitle("Journal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                if journalState.activeEntryID == nil {
                    journalState.openTodaysEntry()
                }
            }
            .accessibilityIdentifier("mobileJournalRoot")
        }
    }
}

private struct MobileJournalBottomBar: View {
    let journalState: NdaniJournalState
    let desktopState: NdaniDesktopState
    let capability: NdaniPlatformCapability

    private var hasContent: Bool {
        !journalState.draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            if let saveError = journalState.saveError {
                Label("Unable to save", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .accessibilityLabel("Save error: \(saveError)")
            } else if let lastSave = journalState.lastSaveDate {
                Label("Saved \(lastSave.formatted(date: .omitted, time: .shortened))", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Label("Not saved yet", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Save") {
                journalState.saveCurrentDraft()
            }
            .buttonStyle(.bordered)
            .disabled(!hasContent)
            .accessibilityIdentifier("mobileJournalSave")

            MobileModelSetupButton(
                desktopState: desktopState,
                capability: capability,
                compact: true
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(NdaniMobileTheme.panel)
    }
}

public struct NdaniMobileChatView: View {
    private let chatState: NdaniChatState
    private let desktopState: NdaniDesktopState
    private let capability: NdaniPlatformCapability
    @State private var showConversationHistory = false

    public init(
        chatState: NdaniChatState,
        desktopState: NdaniDesktopState,
        capability: NdaniPlatformCapability
    ) {
        self.chatState = chatState
        self.desktopState = desktopState
        self.capability = capability
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if let conversation = chatState.activeConversation, !conversation.messages.isEmpty {
                                ForEach(conversation.messages) { message in
                                    MobileChatMessageView(message: message)
                                        .id(message.id)
                                }
                            } else {
                                MobileEmptyChatView(
                                    chatState: chatState,
                                    desktopState: desktopState,
                                    capability: capability
                                )
                            }

                            if chatState.isGenerating && !chatState.streamingResponse.isEmpty {
                                Text(chatState.streamingResponse)
                                    .padding(12)
                                    .background(NdaniMobileTheme.panelStrong)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .id("streaming")
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: chatState.activeConversation?.messages.count) {
                        if let lastID = chatState.activeConversation?.messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }

                MobileChatInputBar(chatState: chatState)
            }
            .background(NdaniMobileTheme.background.ignoresSafeArea())
            .navigationTitle("Chat")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showConversationHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Conversation history")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { chatState.newConversation() }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New conversation")
                }
            }
            #else
            .toolbar {
                Button(action: { showConversationHistory = true }) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Conversation history")
                Button(action: { chatState.newConversation() }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New conversation")
            }
            #endif
            .sheet(isPresented: $showConversationHistory) {
                MobileConversationHistorySheet(
                    chatState: chatState,
                    isPresented: $showConversationHistory
                )
            }
            .accessibilityIdentifier("mobileChatRoot")
        }
    }
}

private struct MobileConversationHistorySheet: View {
    let chatState: NdaniChatState
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(chatState.conversations) { conv in
                    Button(action: {
                        chatState.selectConversation(conv.id)
                        isPresented = false
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conv.title)
                                .font(.headline)
                                .lineLimit(1)
                            Text(conv.lastMessagePreview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(conv.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            chatState.deleteConversation(conv.id)
                        }
                    }
                }
            }
            .navigationTitle("Conversations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}

private struct MobileEmptyChatView: View {
    let chatState: NdaniChatState
    let desktopState: NdaniDesktopState
    let capability: NdaniPlatformCapability

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Start a private chat")
                .font(.title2.weight(.semibold))
            Text("Messages stay on this device. Set up private AI when this iPhone can run the baseline model.")
                .font(.callout)
                .foregroundStyle(NdaniMobileTheme.secondaryText)
                .multilineTextAlignment(.center)
            MobileModelSetupButton(
                desktopState: desktopState,
                capability: capability,
                compact: false
            )
            Button("New conversation") {
                chatState.newConversation()
            }
            .buttonStyle(.borderedProminent)
            .tint(NdaniMobileTheme.accent)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .accessibilityIdentifier("mobileChatEmpty")
    }
}

private struct MobileChatMessageView: View {
    let message: NdaniChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 44)
            }

            Text(message.content)
                .padding(12)
                .background(message.role == .user ? NdaniMobileTheme.accentMuted : NdaniMobileTheme.panelStrong)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if message.role != .user {
                Spacer(minLength: 44)
            }
        }
    }
}

private struct MobileChatInputBar: View {
    let chatState: NdaniChatState

    var body: some View {
        VStack(spacing: 0) {
            if let saveError = chatState.saveError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text("Unable to save: \(saveError)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
                .accessibilityLabel("Save error: \(saveError)")
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: Binding(
                    get: { chatState.draftMessage },
                    set: { chatState.draftMessage = $0 }
                ), axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(10)
                .background(NdaniMobileTheme.panelStrong)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(NdaniMobileTheme.border)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("mobileChatInput")

                if chatState.isGenerating {
                    Button(action: { chatState.stopGenerating() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("Stop generating")
                } else {
                    Button(action: { chatState.sendMessage() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(chatState.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send message")
                }
            }
            .padding(12)
            .background(NdaniMobileTheme.panel)
        }
    }
}

public struct NdaniMobileDashboardView: View {
    private let capability: NdaniPlatformCapability
    private let memoryState: NdaniMemoryState
    private let desktopState: NdaniDesktopState

    public init(
        capability: NdaniPlatformCapability,
        memoryState: NdaniMemoryState,
        desktopState: NdaniDesktopState
    ) {
        self.capability = capability
        self.memoryState = memoryState
        self.desktopState = desktopState
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hapo Ndani")
                            .font(.largeTitle.bold())
                        Text("Private journal, chat, and memory on \(capability.platform.title).")
                            .font(.headline)
                            .foregroundStyle(NdaniMobileTheme.secondaryText)
                    }

                    MobileCapabilityCard(title: "Recommended mode", value: capability.mode.title, detail: capability.mode.userPromise)
                    MobileCapabilityCard(
                        title: "Model download",
                        value: capability.recommendedDownloadTitle,
                        detail: capability.mode.recommendedTier?.modelLabel ?? "This device should capture privately first, then continue on iPad or Mac."
                    )

                    MobilePrivateAISetupCard(
                        desktopState: desktopState,
                        capability: capability
                    )

                    MobileInfoPanel(title: "Privacy baseline") {
                        Label("No analytics or tracking", systemImage: "checkmark.shield")
                        Label("No hosted inference by default", systemImage: "lock")
                        Label("User-approved files only", systemImage: "folder.badge.questionmark")
                    }

                    if !capability.limitations.isEmpty {
                        MobileInfoPanel(title: "Device boundaries") {
                            ForEach(capability.limitations, id: \.self) { limitation in
                                Label(limitation, systemImage: "info.circle")
                            }
                        }
                    }

                    MobileInfoPanel(title: "Local memory") {
                        Text("\(memoryState.lineCount) memory lines")
                            .font(.headline)
                        Text("Mobile keeps the same memory engine, with stricter device-sized boundaries.")
                            .font(.callout)
                            .foregroundStyle(NdaniMobileTheme.secondaryText)
                    }
                }
                .padding()
                .padding(.bottom, 112)
            }
            .background(NdaniMobileTheme.background.ignoresSafeArea())
            .navigationTitle("Home")
        }
    }
}

private struct MobilePrivateAISetupCard: View {
    let desktopState: NdaniDesktopState
    let capability: NdaniPlatformCapability

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Private AI setup")
                    .font(.headline)
                Spacer()
                Text(setupSummary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(summaryColor)
            }

            Text(setupDetail)
                .font(.callout)
                .foregroundStyle(NdaniMobileTheme.secondaryText)

            MobileModelSetupButton(
                desktopState: desktopState,
                capability: capability,
                compact: false
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NdaniMobileTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(NdaniMobileTheme.border)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("mobilePrivateAISetup")
    }

    private var setupSummary: String {
        if capability.mode.recommendedTier == nil {
            return "Capture only"
        }
        guard let package = desktopState.recommendedPackage(for: capability) else {
            return "Not configured"
        }
        switch desktopState.modelDownloader.statuses[package.id] {
        case .inProgress:
            return "Setting up"
        case .done:
            return "Downloaded"
        case .failed:
            return "Needs retry"
        case nil:
            break
        }
        return desktopState.status(for: package)?.isInstalled == true ? "Downloaded" : "Ready to set up"
    }

    private var setupDetail: String {
        guard capability.mode.recommendedTier != nil else {
            return "This iPhone keeps journal and memory capture local, then continues heavier AI on iPad or Mac."
        }
        guard let package = desktopState.recommendedPackage(for: capability) else {
            return "The app could not find a matching package for this device profile."
        }
        if desktopState.status(for: package)?.isInstalled == true {
            if package.runtimeAdapter.hasInProcessLoader {
                return "The recommended package is on this device. Chat and journal can attach it when opened."
            }
            return "The recommended package is on this device, but the matching mobile runtime loader is not bundled yet."
        }
        return "Hapo Ndani only offers chat setup here when the device can run the baseline local model."
    }

    private var summaryColor: Color {
        switch setupSummary {
        case "Downloaded":
            return .green
        case "Needs retry":
            return .red
        case "Capture only":
            return .secondary
        default:
            return .orange
        }
    }
}

private struct MobileModelSetupButton: View {
    let desktopState: NdaniDesktopState
    let capability: NdaniPlatformCapability
    let compact: Bool

    var body: some View {
        if let package = desktopState.recommendedPackage(for: capability) {
            if compact {
                setupButton(for: package)
                    .buttonStyle(.borderless)
            } else {
                setupButton(for: package)
                    .buttonStyle(.borderedProminent)
                    .tint(NdaniMobileTheme.accent)
            }
        } else {
            Label("Capture only", systemImage: "square.and.pencil")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("mobileJournalModelStatus")
        }
    }

    private func setupButton(for package: NdaniLocalModelPackage) -> some View {
        Button(action: { desktopState.downloadModel(package) }) {
            Label(label(for: package), systemImage: icon(for: package))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .font(.caption.weight(.medium))
        .disabled(isDisabled(for: package))
        .accessibilityIdentifier("mobileModelSetupButton")
    }

    private func label(for package: NdaniLocalModelPackage) -> String {
        switch desktopState.modelDownloader.statuses[package.id] {
        case .inProgress:
            return "Setting up..."
        case .done:
            return compact ? "Downloaded" : "Recommended AI downloaded"
        case .failed:
            return "Retry setup"
        case nil:
            break
        }

        if desktopState.status(for: package)?.isInstalled == true {
            return compact ? "Downloaded" : "Recommended AI downloaded"
        }
        return compact ? "Set up AI" : "Set up recommended AI"
    }

    private func icon(for package: NdaniLocalModelPackage) -> String {
        switch desktopState.modelDownloader.statuses[package.id] {
        case .inProgress:
            return "arrow.down.circle"
        case .done:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case nil:
            break
        }
        return desktopState.status(for: package)?.isInstalled == true ? "checkmark.circle.fill" : "sparkle"
    }

    private func isDisabled(for package: NdaniLocalModelPackage) -> Bool {
        if case .inProgress = desktopState.modelDownloader.statuses[package.id] {
            return true
        }
        return package.downloadURL == nil || desktopState.status(for: package)?.isInstalled == true
    }
}

private struct MobileCapabilityCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
            Text(detail).font(.callout).foregroundStyle(NdaniMobileTheme.secondaryText)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NdaniMobileTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(NdaniMobileTheme.border)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct MobileInfoPanel<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NdaniMobileTheme.secondaryText)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NdaniMobileTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(NdaniMobileTheme.border)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
