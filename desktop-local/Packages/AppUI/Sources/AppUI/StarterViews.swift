import AppCore
import AppDocuments
import AppIntegrations
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import SwiftUI

public struct UtilityDashboardView: View {
    private let state: NdaniDesktopState
    private let memoryState: NdaniMemoryState?
    private let openChat: () -> Void
    private let openJournal: () -> Void
    @State private var advancedExpanded = false

    public init(
        state: NdaniDesktopState,
        memoryState: NdaniMemoryState? = nil,
        openChat: @escaping () -> Void = {},
        openJournal: @escaping () -> Void = {}
    ) {
        self.state = state
        self.memoryState = memoryState
        self.openChat = openChat
        self.openJournal = openJournal
    }

    public var body: some View {
        ZStack {
            DashboardTheme.background.ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    DashboardHeader(
                        isReady: state.launchableModelCount > 0,
                        modelLabel: friendlyModelLabel
                    )

                    PrimaryActionPanel(
                        title: primaryActionTitle,
                        detail: primaryActionDetail,
                        icon: primaryActionIcon,
                        actionTitle: primaryActionButtonTitle,
                        secondaryActions: secondaryPrimaryActions,
                        action: primaryAction
                    ) { secondary in
                        switch secondary {
                        case .journal:
                            openJournal()
                        case .folder:
                            chooseFolder()
                        }
                    }

                    DashboardPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Setup")
                                .font(.title3.weight(.semibold))
                            SetupStepRow(
                                number: "1",
                                title: "Private AI model",
                                detail: state.launchableModelCount > 0 ? "\(friendlyModelLabel) is ready." : "Download the recommended Large model.",
                                isDone: state.launchableModelCount > 0,
                                symbol: "sparkles"
                            )
                            SetupStepRow(
                                number: "2",
                                title: "Files Hapo Ndani may read",
                                detail: state.allowedFolderCount == 0 ? "Optional. Add a folder only when you want file help." : "\(state.allowedFolderCount) folder\(state.allowedFolderCount == 1 ? "" : "s") approved.",
                                isDone: state.allowedFolderCount > 0,
                                symbol: "folder.badge.gearshape"
                            )
                            SetupStepRow(
                                number: "3",
                                title: "Start talking or journaling",
                                detail: "Use the app like a private assistant, not a settings panel.",
                                isDone: state.launchableModelCount > 0,
                                symbol: "bubble.left.and.text.bubble.right.fill"
                            )
                        }
                    }

                    DashboardPanel {
                        DisclosureGroup(isExpanded: $advancedExpanded) {
                            VStack(alignment: .leading, spacing: 18) {
                                AdvancedModelSetupView(state: state)
                                ApprovedFoldersAdvancedView(state: state, chooseFolder: chooseFolder)
                                if let memoryState {
                                    MemoryView(memoryState: memoryState)
                                }
                                LocalReadLedgerView(state: state)
                                DataVaultView(state: state)
                                AppUpdaterView(updater: state.appUpdater)
                                PlatformMapView()
                            }
                            .padding(.top, 14)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundStyle(DashboardTheme.gold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Advanced Options")
                                        .font(.title3.weight(.semibold))
                                    Text("Models, smoke tests, ledgers, vault, updates, and platform settings")
                                        .font(.caption)
                                        .foregroundStyle(DashboardTheme.muted)
                                }
                            }
                        }
                    }

                    AboutNdaniView()
                }
                .padding(24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(minWidth: 900, maxHeight: .infinity)
    }

    private var friendlyModelLabel: String {
        if let ready = state.preferredLaunchableModelStatus() {
            return "\(ready.package.tier.title) private AI model"
        }
        if state.installedModelCount > 0 {
            return "Model needs setup"
        }
        return "No model installed"
    }

    private var primaryActionTitle: String {
        if state.launchableModelCount == 0 {
            "Set up private AI"
        } else if state.allowedFolders.isEmpty {
            "Start a real conversation"
        } else {
            "Everything important is ready"
        }
    }

    private var primaryActionDetail: String {
        if state.launchableModelCount == 0 {
            "Download the Large model so chat sounds human instead of scripted."
        } else if state.allowedFolders.isEmpty {
            "Chat works now. Add a folder only when you want Hapo Ndani to help with local files."
        } else {
            "Chat, journal, memory, and approved files are available."
        }
    }

    private var primaryActionIcon: String {
        state.launchableModelCount == 0 ? "arrow.down.circle.fill" : "bubble.left.and.text.bubble.right.fill"
    }

    private var primaryActionButtonTitle: String {
        state.launchableModelCount == 0 ? "Download Large Model" : "Open Chat"
    }

    private var secondaryPrimaryActions: [PrimaryActionPanel.SecondaryAction] {
        state.launchableModelCount == 0 ? [] : [.journal, .folder]
    }

    private func primaryAction() {
        if state.launchableModelCount == 0,
           let package = NdaniDesktopState.recommendedPackage(for: .desktop) {
            state.downloadModel(package)
        } else {
            openChat()
        }
    }

    private func chooseFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Allow"
        panel.message = "Choose a folder Hapo Ndani Desktop can use locally."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try state.addAllowedFolder(url: url)
        } catch {
            state.addAllowedFolder(displayName: url.lastPathComponent, path: url.path)
        }
        #endif
    }

    private func modelExplanation(for tier: NdaniModelTier) -> String {
        switch tier {
        case .phone:
            "4B Lite profile for mobile-class hardware. This is the conversational floor."
        case .desktop:
            "12B-14B Large profile for laptops and desktops, with 8B Standard fallback on low-memory devices."
        case .workstation:
            "Future extra-large local downloads after hardware checks."
        }
    }
}

private typealias DashboardTheme = NdaniTheme

private struct DashboardHeader: View {
    let isReady: Bool
    let modelLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hapo Ndani")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardTheme.text)
                Text("Private AI for chat, journal, memory, and files.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(DashboardTheme.muted)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(isReady ? DashboardTheme.mint : DashboardTheme.gold)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isReady ? "Ready to talk" : "Setup needed")
                        .font(.headline)
                        .foregroundStyle(DashboardTheme.text)
                    Text(modelLabel)
                        .font(.caption)
                        .foregroundStyle(DashboardTheme.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(DashboardTheme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DashboardTheme.border))
        }
    }
}

private struct PrimaryActionPanel: View {
    enum SecondaryAction: CaseIterable {
        case journal
        case folder

        var title: String {
            switch self {
            case .journal:
                "Open Journal"
            case .folder:
                "Allow Folder"
            }
        }

        var symbol: String {
            switch self {
            case .journal:
                "book.closed.fill"
            case .folder:
                "folder.badge.plus"
            }
        }
    }

    let title: String
    let detail: String
    let icon: String
    let actionTitle: String
    let secondaryActions: [SecondaryAction]
    let action: () -> Void
    let secondaryAction: (SecondaryAction) -> Void

    var body: some View {
        DashboardPanel {
            HStack(alignment: .center, spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(DashboardTheme.gold)
                    .frame(width: 54, height: 54)
                    .background(DashboardTheme.gold.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DashboardTheme.text)
                    Text(detail)
                        .font(.body)
                        .foregroundStyle(DashboardTheme.muted)
                        .lineLimit(2)
                }
                Spacer()
                HStack(spacing: 8) {
                    ForEach(secondaryActions, id: \.self) { secondary in
                        Button(action: { secondaryAction(secondary) }) {
                            Label(secondary.title, systemImage: secondary.symbol)
                        }
                        .buttonStyle(DashboardSecondaryButtonStyle())
                    }
                    Button(actionTitle, action: action)
                        .buttonStyle(DashboardPrimaryButtonStyle())
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }
}

private struct DashboardPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardTheme.panel)
            .foregroundStyle(DashboardTheme.text)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DashboardTheme.border))
    }
}

private struct DashboardPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(DashboardTheme.mint.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct DashboardSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(DashboardTheme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DashboardTheme.panelRaised.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DashboardTheme.border))
    }
}

private struct StatusCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(DashboardTheme.mint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardTheme.muted)
            }
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(DashboardTheme.text)
            Text(detail)
                .font(.callout)
                .foregroundStyle(DashboardTheme.muted)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DashboardTheme.border))
    }
}

private struct SetupStepRow: View {
    let number: String
    let title: String
    let detail: String
    let isDone: Bool
    let symbol: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDone ? DashboardTheme.mint.opacity(0.18) : DashboardTheme.panelRaised)
                    .frame(width: 42, height: 42)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(DashboardTheme.mint)
                } else {
                    Text(number)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(DashboardTheme.gold)
                }
            }

            Image(systemName: symbol)
                .foregroundStyle(isDone ? DashboardTheme.mint : DashboardTheme.gold)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DashboardTheme.text)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(DashboardTheme.muted)
            }
            Spacer()
        }
        .padding(12)
        .background(DashboardTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AdvancedModelSetupView: View {
    let state: NdaniDesktopState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model Setup")
                .font(.headline)
            Picker(
                "Default model tier",
                selection: Binding(
                    get: { state.selectedTier },
                    set: { state.selectedTier = $0 }
                )
            ) {
                ForEach(NdaniModelTier.allCases, id: \.self) { tier in
                    Text(tier.title).tag(tier)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text(state.modelDirectory.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(DashboardTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Refresh") {
                    state.refreshModelStatuses()
                }
            }

            ForEach(state.modelStatuses) { status in
                LocalModelRow(
                    status: status,
                    smokeTestResult: state.smokeTestResult(for: status),
                    downloadStatus: state.modelDownloader.statuses[status.package.id],
                    onSmokeTest: { state.runSmokeTest(for: status) },
                    onDownload: { state.downloadModel(status.package) }
                )
            }
        }
    }
}

private struct ApprovedFoldersAdvancedView: View {
    let state: NdaniDesktopState
    let chooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Approved Folders")
                    .font(.headline)
                Spacer()
                Text("\(state.allowedFolderCount) approved")
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.muted)
                Button("Allow folder", action: chooseFolder)
                Button("Revoke all") {
                    state.revokeAllFolders()
                }
                .disabled(state.allowedFolders.isEmpty)
            }

            if state.allowedFolders.isEmpty {
                Text("No folders approved.")
                    .foregroundStyle(DashboardTheme.muted)
            } else {
                ForEach(state.allowedFolders) { folder in
                    AllowedFolderRow(folder: folder) {
                        state.revokeAllowedFolder(id: folder.id)
                    }
                }
            }
        }
    }
}

private struct LocalReadLedgerView: View {
    let state: NdaniDesktopState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Local Read Ledger")
                    .font(.headline)
                Spacer()
                Text("\(state.localReadLedger.count) recorded")
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.muted)
                Button("Clear ledger") {
                    state.clearLocalReadLedger()
                }
                .disabled(state.localReadLedger.isEmpty)
            }

            if state.localReadLedger.isEmpty {
                Text("No local reads recorded yet.")
                    .foregroundStyle(DashboardTheme.muted)
            } else {
                ForEach(state.localReadLedger.prefix(5)) { entry in
                    LocalReadLedgerRow(entry: entry)
                }
            }
        }
    }
}

private struct PlatformMapView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Platform Map")
                .font(.headline)
            PlatformRow(title: "Desktop first", detail: "Stronger local models, larger files, longer sessions.")
            PlatformRow(title: "Phone next", detail: "Portable memory, quick voice, permission prompts.")
            PlatformRow(title: "PC later", detail: "Same local-service shape once the Mac proof works.")
        }
    }
}

private struct LocalModelRow: View {
    let status: NdaniLocalModelStatus
    let smokeTestResult: NdaniSmokeTestResult?
    let downloadStatus: NdaniModelDownloader.Status?
    let onSmokeTest: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.isInstalled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(status.isInstalled ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(status.package.title)
                        .font(.headline)
                    Text(status.package.tier.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(status.package.detail)
                    .foregroundStyle(.secondary)
                Text(status.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let smokeTestResult {
                    Text(smokeTestResult.detail)
                        .font(.caption)
                        .foregroundStyle(smokeTestResult.status == .passed ? .green : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if case .failed(let reason) = downloadStatus {
                    Text("Download failed: \(reason)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(status.statusLabel)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(readinessColor)
                if let smokeTestResult {
                    Text(smokeTestResult.status.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(smokeTestResult.status == .passed ? .green : .secondary)
                }
                if status.readiness == .missing, status.package.downloadURL != nil {
                    if case .inProgress(let fraction) = downloadStatus {
                        HStack(spacing: 4) {
                            ProgressView(value: fraction)
                                .progressViewStyle(.linear)
                                .frame(width: 80)
                            Text("\(Int(fraction * 100))%").font(.caption)
                        }
                    } else {
                        Button("Download", action: onDownload)
                    }
                }
                Button("Smoke test", action: onSmokeTest)
                    .disabled(status.canLaunchRuntime == false)
            }
        }
        .padding(.vertical, 4)
    }

    private var readinessColor: Color {
        switch status.readiness {
        case .missing:
            .secondary
        case .blocked, .invalid, .formatMismatch, .hashMismatch, .hardwareCheckRequired, .loaderMissing:
            .orange
        case .ready:
            .green
        }
    }
}

private struct AllowedFolderRow: View {
    let folder: NdaniAllowedFolder
    let revoke: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: folder.isBookmarkStale ? "folder.badge.questionmark" : "folder.badge.gearshape")
                .foregroundStyle(folder.isBookmarkStale ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.displayName)
                    .font(.headline)
                Text(folder.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if folder.bookmarkData != nil {
                    Text(folder.isBookmarkStale ? "Permission needs refresh" : "Permission saved")
                        .font(.caption)
                        .foregroundStyle(folder.isBookmarkStale ? .orange : .secondary)
                }
            }
            Spacer()
            Button("Revoke", action: revoke)
        }
    }
}

private struct LocalReadResultView: View {
    let result: NdaniLocalReadResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(result.status == .ready ? .green : .orange)
                Text(result.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let preview = result.preview {
                Text(preview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct LocalReadLedgerRow: View {
    let entry: NdaniLocalReadLedgerEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.status == .ready ? "checkmark.shield" : "exclamationmark.shield")
                .foregroundStyle(entry.status == .ready ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No file")
                        .font(.headline)
                    Text(entry.status.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let folderPath = entry.folderPath {
                    Text(folderPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text("\(entry.previewLength) preview chars - \(entry.wasSentOffDevice ? "sent" : "not sent")")
                    .font(.caption)
                    .foregroundStyle(entry.wasSentOffDevice ? .orange : .secondary)
            }
            Spacer()
            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct DataVaultView: View {
    let state: NdaniDesktopState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Wording is deliberately literal. The submission carries a licence
            // key, so it is pseudonymous, not anonymous — and this client cannot
            // verify any buyer, so it does not call one verified.
            Text("Write a short summary in your own words and submit it to a buyer for payment. Only the text you type is sent — never your files, and never automatically. A submission is linked to your participant id, so it is not anonymous. Offers and payment come from whichever rail this build is configured to use.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let result = state.vaultLastResult {
                VaultResultView(result: result)
            } else {
                VaultFormView(state: state)
            }

            if let error = state.vaultErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VaultFormView: View {
    let state: NdaniDesktopState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Participant ID").font(.caption).foregroundStyle(.secondary)
                    TextField("NDANI-XXXX-…", text: Binding(
                        get: { state.vaultParticipantID },
                        set: { state.vaultParticipantID = $0 }
                    ))
                    .font(.caption.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Data type").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { state.vaultSelectedType },
                        set: { state.vaultSelectedType = $0 }
                    )) {
                        ForEach(NdaniVaultDataType.allCases) { dt in
                            Text(dt.title).tag(dt)
                        }
                    }
                    .frame(width: 180)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Offer title").font(.caption).foregroundStyle(.secondary)
                TextField("One-line description of what you're offering", text: Binding(
                    get: { state.vaultTitle },
                    set: { state.vaultTitle = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Your summary (max 1200 chars — you write it, you control it)")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { state.vaultSummary },
                    set: { state.vaultSummary = $0 }
                ))
                .font(.callout)
                .frame(minHeight: 80, maxHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                if !state.vaultSummary.isEmpty {
                    Text("\(state.vaultSummary.count)/1200")
                        .font(.caption2)
                        .foregroundStyle(state.vaultSummary.count > 1100 ? .orange : .secondary)
                } else {
                    Text(state.vaultSelectedType.placeholder)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Button(state.vaultSubmitting ? "Submitting…" : "Submit offer") {
                    state.submitVaultOffer()
                }
                .disabled(
                    state.vaultSubmitting ||
                    state.vaultParticipantID.isEmpty ||
                    state.vaultTitle.isEmpty ||
                    state.vaultSummary.isEmpty ||
                    state.vaultSummary.count > 1200
                )
                Text("Nothing is read automatically. Only what you write here is sent.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct VaultResultView: View {
    let result: NdaniVaultOfferResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Offer submitted — $\(String(format: "%.2f", result.creditAmountUSD)) added to balance")
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Credit code — click to copy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(result.creditCode)
                    .font(.headline.monospaced())
                    .foregroundStyle(.purple)
                    .onTapGesture {
                        copyCreditCode(result.creditCode)
                    }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(result.message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private func copyCreditCode(_ code: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(code, forType: .string)
    #elseif os(iOS)
    UIPasteboard.general.string = code
    #endif
}

private struct AppUpdaterView: View {
    let updater: NdaniAppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Updates are never automatic. Tap below to check on your own terms.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let info = updater.updateInfo {
                if updater.hasUpdate {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Version \(info.version) available")
                                .font(.headline)
                            Text(info.releaseNotes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            Text("macOS \(info.minMacOS)+ · Released \(info.releasedAt)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Link("Download", destination: info.downloadURL)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("You're on the latest version (\(NdaniAppUpdater.currentVersion)).")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let err = updater.checkError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button(updater.isChecking ? "Checking…" : "Check for updates") {
                updater.checkForUpdate()
            }
            .disabled(updater.isChecking)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlatformRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - About Ndani

private struct AboutNdaniView: View {
    var body: some View {
        DashboardPanel {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 28))
                        .foregroundStyle(DashboardTheme.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("About Hapo Ndani")
                            .font(.title3.weight(.semibold))
                        Text("Private AI that runs on your machine.")
                            .font(.callout)
                            .foregroundStyle(DashboardTheme.muted)
                    }
                }

                // Privacy & Security
                VStack(alignment: .leading, spacing: 10) {
                    AboutSectionHeader(title: "Privacy & Security", symbol: "lock.shield.fill")

                    AboutBadge(
                        symbol: "cpu",
                        title: "100% on-device inference",
                        detail: "Your conversations never leave this machine. The AI model runs locally with no cloud calls."
                    )
                    AboutBadge(
                        symbol: "lock.fill",
                        title: "AES-256-GCM encryption at rest",
                        detail: "All stored data — conversations, journal entries, memories, and permissions — is encrypted using AES-GCM with a device-only Keychain key."
                    )
                    AboutBadge(
                        symbol: "key.fill",
                        title: "macOS Keychain key storage",
                        detail: "The encryption key is stored in the Secure Enclave-backed Keychain, locked to this device and accessible only when unlocked."
                    )
                    AboutBadge(
                        symbol: "iphone.and.arrow.forward",
                        title: "iOS Data Protection",
                        detail: "On iOS, all files use NSFileProtectionComplete — data is inaccessible when the device is locked."
                    )
                    AboutBadge(
                        symbol: "network.slash",
                        title: "No telemetry, no analytics",
                        detail: "Zero tracking. No usage data, crash reports, or identifiers are sent anywhere. Ever."
                    )
                    AboutBadge(
                        symbol: "folder.badge.gearshape",
                        title: "Explicit file permissions",
                        detail: "Hapo Ndani can only read folders you approve. Every file access is logged in the local read ledger."
                    )
                    AboutBadge(
                        symbol: "doc.text.magnifyingglass",
                        title: "Prompt injection defense",
                        detail: "File contents are wrapped in structured delimiters and the model is instructed to treat them as data, not instructions."
                    )
                    AboutBadge(
                        symbol: "arrow.clockwise.circle",
                        title: "Manual updates only",
                        detail: "Updates are never automatic. You decide when to check and what to install."
                    )
                    AboutBadge(
                        symbol: "icloud.slash",
                        title: "No cloud backup",
                        detail: "All Hapo Ndani data is excluded from iCloud, Time Machine, and Finder backups by default."
                    )
                }

                Divider().overlay(DashboardTheme.border)

                // Built With
                VStack(alignment: .leading, spacing: 10) {
                    AboutSectionHeader(title: "Built With", symbol: "wrench.and.screwdriver.fill")

                    AboutStatRow(label: "Platform", value: "SwiftUI · Swift 6 strict concurrency")
                    AboutStatRow(label: "Inference", value: "llama.cpp (in-process, Metal-accelerated)")
                    AboutStatRow(label: "Encryption", value: "Apple CryptoKit AES-256-GCM")
                    AboutStatRow(label: "Key storage", value: "macOS Keychain Services")
                    AboutStatRow(label: "Architecture", value: "Swift Package modules (AppCore, AppUI, AppInference, AppIntegrations)")
                    AboutStatRow(label: "Concurrency", value: "@MainActor isolation · Serial DispatchQueues · NSLock")
                    AboutStatRow(label: "Persistence", value: "JSON flat files, encrypted, per-entity")
                    AboutStatRow(label: "Memory", value: "DispatchSource memory pressure monitoring, auto-unload")
                    AboutStatRow(label: "Hash verification", value: "Streaming SHA-256 via CryptoKit (chunked FileHandle reads)")
                    AboutStatRow(label: "Supported models", value: "GGUF (llama.cpp) · LiteRT-LM (future)")
                    #if os(iOS)
                    AboutStatRow(label: "File protection", value: "NSFileProtectionComplete")
                    #endif
                }

                Divider().overlay(DashboardTheme.border)

                // Footer
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ni Biashara LLC · Dallas, TX")
                        .font(.caption)
                        .foregroundStyle(DashboardTheme.muted)
                    Text("Hapo Ndani means \"right here inside\" in Swahili. Your data stays right here inside your machine.")
                        .font(.caption)
                        .foregroundStyle(DashboardTheme.muted.opacity(0.75))
                }
            }
        }
    }
}

private struct AboutSectionHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(DashboardTheme.gold)
            Text(title)
                .font(.headline)
        }
    }
}

private struct AboutBadge: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(DashboardTheme.mint)
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AboutStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(DashboardTheme.muted)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(DashboardTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MemoryView: View {
    let memoryState: NdaniMemoryState
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What Hapo Ndani remembers about you")
                        .font(.headline)
                    Text("\(memoryState.lineCount) memories stored locally")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if memoryState.isExtracting {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Learning...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        memoryState.save()
                    }
                    isEditing.toggle()
                }
                .buttonStyle(.bordered)
                if !memoryState.isEmpty {
                    Button("Clear", role: .destructive) {
                        memoryState.clear()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if memoryState.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .foregroundStyle(.secondary)
                    Text("No memories yet. Write journal entries and tap Reflect — Hapo Ndani will learn about you over time.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if isEditing {
                TextEditor(text: Binding(
                    get: { memoryState.content },
                    set: { memoryState.content = $0 }
                ))
                .font(.callout.monospaced())
                .frame(minHeight: 120, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(
                        memoryState.content
                            .components(separatedBy: .newlines)
                            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            .prefix(10),
                        id: \.self
                    ) { line in
                        Text(line)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                    if memoryState.lineCount > 10 {
                        Text("+ \(memoryState.lineCount - 10) more")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                Text("Stored in Hapo Ndani's local application support folder — never leaves this machine.")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct StarterSettingsView: View {
    private let state: NdaniDesktopState

    public init(state: NdaniDesktopState) {
        self.state = state
    }

    public var body: some View {
        Form {
            Picker(
                "Default model tier",
                selection: Binding(
                    get: { state.selectedTier },
                    set: { state.selectedTier = $0 }
                )
            ) {
                ForEach(NdaniModelTier.allCases, id: \.self) { tier in
                    Text(tier.title).tag(tier)
                }
            }
            HStack {
                Text("Local runtime")
                Spacer()
                Text(state.localRuntimeEnabled ? "Service ready" : "Not connected")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Model packages")
                Spacer()
                Text(state.modelStatusSummary)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Approved folders")
                Spacer()
                Text("\(state.allowedFolderCount)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Hosted inference")
                Spacer()
                Text(state.hostedInferenceEnabled ? "Enabled by consent" : "Off")
                    .foregroundStyle(.secondary)
            }
            Text("Hosted inference is not part of the default private path.")
                .foregroundStyle(.secondary)
        }
    }
}

public struct StarterMenuBarView: View {
    private let state: NdaniDesktopState

    public init(state: NdaniDesktopState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hapo Ndani Desktop")
                .font(.headline)
            Text(state.selectedTier.modelLabel)
                .foregroundStyle(.secondary)
            Button("Use Large tier") {
                state.selectedTier = .desktop
            }
            Button("Use Lite tier") {
                state.selectedTier = .phone
            }
        }
        .padding()
        .frame(width: 280)
    }
}

public struct StarterCommandMenu: Commands {
    private let state: NdaniDesktopState

    public init(state: NdaniDesktopState) {
        self.state = state
    }

    public var body: some Commands {
        CommandMenu("Hapo Ndani") {
            Button("Use Lite Tier") {
                state.selectedTier = .phone
            }
            Button("Use Large Tier") {
                state.selectedTier = .desktop
            }
            Button("Use Extra Large Tier") {
                state.selectedTier = .workstation
            }
        }
    }
}
