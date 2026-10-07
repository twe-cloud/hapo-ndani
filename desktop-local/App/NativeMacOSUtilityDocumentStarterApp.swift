import SwiftUI
import AppCore
import AppDocuments
import AppUI
import AppInference

@main
struct NativeMacOSUtilityDocumentStarterApp: App {
    @State private var state: NdaniDesktopState
    @State private var chatState = NdaniChatState()
    @State private var journalState = NdaniJournalState()
    @State private var memoryState = NdaniMemoryState()
    @State private var selectedTab: AppTab = .dashboard

    init() {
        _state = State(initialValue: NdaniDesktopState(
            allowedFolders: NdaniDesktopState.loadAllowedFolders(),
            localReadLedger: NdaniDesktopState.loadLocalReadLedger()
        ))
    }

    enum AppTab: String {
        case dashboard
        case chat
        case journal
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                UtilityDashboardView(
                    state: state,
                    memoryState: memoryState,
                    openChat: { selectedTab = .chat },
                    openJournal: { selectedTab = .journal }
                )
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                    .tag(AppTab.dashboard)

                ChatView(chatState: chatState, desktopState: state)
                    .tabItem {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                        Text("Chat")
                    }
                    .tag(AppTab.chat)

                JournalView(journalState: journalState, desktopState: state)
                    .tabItem {
                        Image(systemName: "book.closed")
                        Text("Journal")
                    }
                    .tag(AppTab.journal)
            }
            .preferredColorScheme(.dark)
            .onAppear {
                connectInferenceEngine()
                connectFolderContext()
                connectMemory()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                journalState.saveCurrentDraft()
                chatState.inferenceEngine?.unload()
                journalState.inferenceEngine?.unload()
            }
            .onChange(of: state.modelStatuses) {
                connectInferenceEngine()
            }
            .onChange(of: state.allowedFolders.count) {
                connectFolderContext()
            }
        }
        .defaultSize(width: 960, height: 760)

        Settings {
            StarterSettingsView(state: state)
                .frame(width: 420)
                .padding()
        }

        DocumentGroup(newDocument: StarterDocument()) { file in
            StarterDocumentView(document: file.$document)
        }

        MenuBarExtra("Hapo Ndani", systemImage: "lock.laptopcomputer") {
            StarterMenuBarView(state: state)
        }
        .menuBarExtraStyle(.window)
        .commands {
            StarterCommandMenu(state: state)
        }
    }

    private func connectMemory() {
        let mem = memoryState
        chatState.memoryProvider = { mem.systemPromptFragment }
        journalState.memoryState = memoryState
    }

    private func connectFolderContext() {
        let desktopState = state
        chatState.folderContextProvider = { desktopState.readApprovedFolderContents() }
        chatState.hasFolderContext = state.hasReadableFolders
    }

    private func connectInferenceEngine() {
        guard let readyModel = state.preferredLaunchableModelStatus() else {
            return
        }

        if chatState.inferenceEngine == nil || chatState.inferenceEngine?.modelName != readyModel.package.title {
            guard let engine = NdaniRuntimeLoader.makeEngine(for: readyModel) else { return }
            chatState.inferenceEngine = engine
            journalState.inferenceEngine = engine
        }
    }
}
