import CryptoKit
import Foundation
import CoreFoundation
import Observation

public enum NdaniModelTier: String, CaseIterable, Sendable {
    case phone
    case desktop
    case workstation

    public var title: String {
        switch self {
        case .phone:
            "Lite"
        case .desktop:
            "Large"
        case .workstation:
            "Extra Large"
        }
    }

    public var modelLabel: String {
        switch self {
        case .phone:
            "4B mobile candidate"
        case .desktop:
            "Qwen3 14B GGUF"
        case .workstation:
            "30B+ local model"
        }
    }
}

public struct NdaniLocalRuntimeAdapter: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let directoryName: String
    public let executableName: String
    public let modelFileExtensions: [String]
    public let minimumModelBytes: Int64
    public let hasInProcessLoader: Bool

    public func executableURL(in runtimeRoots: [URL], fileManager: FileManager = .default) -> URL? {
        runtimeRoots.compactMap { root -> URL? in
            let adapterRoot = root.appendingPathComponent(directoryName, isDirectory: true)
            let candidate = adapterRoot.appendingPathComponent(executableName)
            guard fileManager.isExecutableFile(atPath: candidate.path),
                  Self.isURL(candidate, inside: adapterRoot)
            else {
                return nil
            }
            return candidate
        }
        .first
    }

    public func acceptsModelFile(_ url: URL) -> Bool {
        modelFileExtensions.contains(url.pathExtension.lowercased())
    }

    public func smokeTestArguments(modelPath: String, prompt: String = "Reply with OK.") -> [String] {
        switch id {
        case Self.llamaCpp.id:
            ["-m", modelPath, "-p", prompt, "-n", "8"]
        default:
            ["--model", modelPath, "--prompt", prompt, "--max-tokens", "8"]
        }
    }

    /// Validates a model file by checking its header bytes match the expected format.
    /// Used for sandbox-safe smoke tests (no external process required).
    public func validateModelFile(at url: URL) -> (valid: Bool, detail: String) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return (false, "Cannot open model file.")
        }
        defer { try? handle.close() }

        guard let headerData = try? handle.read(upToCount: 16), headerData.count >= 4 else {
            return (false, "Model file too small to validate.")
        }

        switch id {
        case Self.llamaCpp.id:
            let magic = headerData.prefix(4)
            // GGUF magic: bytes 0x47 0x47 0x55 0x46 ("GGUF")
            let ggufMagic: [UInt8] = [0x47, 0x47, 0x55, 0x46]
            guard magic.elementsEqual(ggufMagic) else {
                return (false, "Not a valid GGUF file.")
            }
            return (true, "Valid GGUF model file.")
        default:
            // LiteRT-LM and other formats: validate file is readable and non-trivial
            return (true, "Model file present and readable.")
        }
    }

    public static let liteRTLM = NdaniLocalRuntimeAdapter(
        id: "litert-lm",
        title: "LiteRT-LM",
        directoryName: "litert-lm",
        executableName: "litertlm",
        modelFileExtensions: ["litertlm"],
        minimumModelBytes: 1,
        hasInProcessLoader: false
    )

    public static let llamaCpp = NdaniLocalRuntimeAdapter(
        id: "llama-cpp",
        title: "llama.cpp",
        directoryName: "llama.cpp",
        executableName: "llama-cli",
        modelFileExtensions: ["gguf"],
        minimumModelBytes: 1,
        hasInProcessLoader: true
    )

    private static func isURL(_ url: URL, inside root: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}

public struct NdaniLocalModelPackage: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let fileName: String
    public let tier: NdaniModelTier
    public let detail: String
    public let runtimeAdapter: NdaniLocalRuntimeAdapter
    public let minimumPhysicalMemoryBytes: UInt64?
    public let expectedSHA256: String?
    /// Direct download URL for this model package.
    /// Fill in once packages are pinned to a release and SHA256 hashes are verified.
    public let downloadURL: URL?

    public init(
        id: String,
        title: String,
        fileName: String,
        tier: NdaniModelTier,
        detail: String,
        runtimeAdapter: NdaniLocalRuntimeAdapter,
        minimumPhysicalMemoryBytes: UInt64? = nil,
        expectedSHA256: String?,
        downloadURL: URL?
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.tier = tier
        self.detail = detail
        self.runtimeAdapter = runtimeAdapter
        self.minimumPhysicalMemoryBytes = minimumPhysicalMemoryBytes
        self.expectedSHA256 = expectedSHA256
        self.downloadURL = downloadURL
    }

    public var runtimeCommand: String {
        runtimeAdapter.executableName
    }

    public func supportsDevice(physicalMemoryBytes: UInt64) -> Bool {
        guard let minimumPhysicalMemoryBytes else { return true }
        return physicalMemoryBytes >= minimumPhysicalMemoryBytes
    }

    public static let recommended: [NdaniLocalModelPackage] = [
        NdaniLocalModelPackage(
            id: "qwen3-4b-gguf",
            title: "Qwen3 4B GGUF",
            fileName: "Qwen3-4B-Q4_K_M.gguf",
            tier: .phone,
            detail: "Lite mobile candidate for capture help and narrow prompts. Not the human conversation baseline.",
            runtimeAdapter: .llamaCpp,
            minimumPhysicalMemoryBytes: 6 * 1024 * 1024 * 1024,
            expectedSHA256: nil,
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/bc640142c66e1fdd12af0bd68f40445458f3869b/Qwen3-4B-Q4_K_M.gguf")
        ),
        NdaniLocalModelPackage(
            id: "gemma-4-e2b-it",
            title: "Gemma 4 E2B IT",
            fileName: "gemma-4-E2B-it.litertlm",
            tier: .phone,
            detail: "Future phone-safe LiteRT profile after Swift loader support lands.",
            runtimeAdapter: .liteRTLM,
            minimumPhysicalMemoryBytes: 6 * 1024 * 1024 * 1024,
            expectedSHA256: nil,
            downloadURL: URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/gemma-4-E2B-it.litertlm")
        ),
        NdaniLocalModelPackage(
            id: "qwen3-14b-gguf",
            title: "Qwen3 14B GGUF",
            fileName: "Qwen3-14B-Q4_K_M.gguf",
            tier: .desktop,
            detail: "Large laptop/desktop default for a real conversational product experience.",
            runtimeAdapter: .llamaCpp,
            minimumPhysicalMemoryBytes: 16 * 1024 * 1024 * 1024,
            expectedSHA256: nil,
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen3-14B-GGUF/resolve/530227a7d994db8eca5ab5ced2fb692b614357fd/Qwen3-14B-Q4_K_M.gguf")
        ),
        NdaniLocalModelPackage(
            id: "qwen3-8b-gguf",
            title: "Qwen3 8B GGUF",
            fileName: "Qwen3-8B-Q4_K_M.gguf",
            tier: .desktop,
            detail: "Standard fallback for low-memory laptops and desktops.",
            runtimeAdapter: .llamaCpp,
            minimumPhysicalMemoryBytes: 8 * 1024 * 1024 * 1024,
            expectedSHA256: nil,
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/7c41481f57cb95916b40956ab2f0b139b296d974/Qwen3-8B-Q4_K_M.gguf")
        ),
        NdaniLocalModelPackage(
            id: "gemma-4-e4b-it",
            title: "Gemma 4 E4B IT",
            fileName: "gemma-4-E4B-it.litertlm",
            tier: .desktop,
            detail: "Future desktop LiteRT profile after Swift loader support lands.",
            runtimeAdapter: .liteRTLM,
            minimumPhysicalMemoryBytes: 8 * 1024 * 1024 * 1024,
            expectedSHA256: nil,
            downloadURL: URL(string: "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/2eee7ac325f20eb8c9ac1d0e972f7c84663062da/gemma-4-E4B-it.litertlm")
        ),
        NdaniLocalModelPackage(
            id: "gemma-4-26b-a4b",
            title: "Gemma 4 26B A4B",
            fileName: "gemma-4-26b-a4b.litertlm",
            tier: .workstation,
            detail: "Future workstation lane after hardware checks.",
            runtimeAdapter: .liteRTLM,
            minimumPhysicalMemoryBytes: 32 * 1024 * 1024 * 1024,
            expectedSHA256: nil,
            downloadURL: nil // TODO: pin after hardware gating is validated
        ),
    ]
}

public enum NdaniRuntimeReadiness: String, Equatable, Sendable {
    case missing
    case blocked
    case invalid
    case formatMismatch
    case hashMismatch
    case hardwareCheckRequired
    case loaderMissing
    case ready

    public var label: String {
        switch self {
        case .missing:
            "Missing"
        case .blocked:
            "Blocked"
        case .invalid:
            "Invalid"
        case .formatMismatch:
            "Wrong format"
        case .hashMismatch:
            "Hash mismatch"
        case .hardwareCheckRequired:
            "Hardware check"
        case .loaderMissing:
            "Loader missing"
        case .ready:
            "Ready"
        }
    }
}

public struct NdaniLocalModelStatus: Identifiable, Equatable, Sendable {
    public let package: NdaniLocalModelPackage
    public let path: String
    public let byteCount: Int64?
    public let readiness: NdaniRuntimeReadiness

    public var id: String { package.id }
    public var isInstalled: Bool { byteCount != nil }
    public var canLaunchRuntime: Bool { readiness == .ready }

    public var statusLabel: String {
        switch readiness {
        case .missing:
            "Not installed"
        case .blocked:
            "Access blocked"
        case .invalid:
            "Needs valid package"
        case .formatMismatch:
            "Wrong model format"
        case .hashMismatch:
            "Model hash mismatch"
        case .hardwareCheckRequired:
            "Needs hardware check"
        case .loaderMissing:
            "Install local loader"
        case .ready:
            "Ready to load"
        }
    }
}

public enum NdaniSmokeTestStatus: String, Equatable, Sendable {
    case notReady
    case passed
    case failed
    case timedOut

    public var label: String {
        switch self {
        case .notReady:
            "Not ready"
        case .passed:
            "Smoke passed"
        case .failed:
            "Smoke failed"
        case .timedOut:
            "Smoke timed out"
        }
    }
}

public struct NdaniSmokeTestResult: Equatable, Sendable {
    public let status: NdaniSmokeTestStatus
    public let detail: String

    public static let notReady = NdaniSmokeTestResult(
        status: .notReady,
        detail: "Model package is not runtime-ready."
    )
}

public struct NdaniAllowedFolder: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let path: String
    public let bookmarkData: Data?
    public let isBookmarkStale: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        path: String,
        bookmarkData: Data? = nil,
        isBookmarkStale: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.bookmarkData = bookmarkData
        self.isBookmarkStale = isBookmarkStale
    }
}

public enum NdaniLocalReadStatus: String, Codable, Equatable, Sendable {
    case noFolder
    case stalePermission
    case accessDenied
    case outsideApprovedFolder
    case missingFile
    case unreadable
    case ready

    public var label: String {
        switch self {
        case .noFolder:
            "No folder"
        case .stalePermission:
            "Permission stale"
        case .accessDenied:
            "Access denied"
        case .outsideApprovedFolder:
            "Outside approved folder"
        case .missingFile:
            "Missing file"
        case .unreadable:
            "Unreadable"
        case .ready:
            "Ready"
        }
    }
}

public struct NdaniLocalReadResult: Equatable, Sendable {
    public let status: NdaniLocalReadStatus
    public let detail: String
    public let preview: String?
    public let folderPath: String?
    public let filePath: String?

    public init(
        status: NdaniLocalReadStatus,
        detail: String,
        preview: String?,
        folderPath: String? = nil,
        filePath: String? = nil
    ) {
        self.status = status
        self.detail = detail
        self.preview = preview
        self.folderPath = folderPath
        self.filePath = filePath
    }
}

public struct NdaniLocalReadLedgerEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let folderPath: String?
    public let filePath: String?
    public let status: NdaniLocalReadStatus
    public let previewLength: Int
    public let wasSentOffDevice: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        folderPath: String?,
        filePath: String?,
        status: NdaniLocalReadStatus,
        previewLength: Int,
        wasSentOffDevice: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.folderPath = folderPath
        self.filePath = filePath
        self.status = status
        self.previewLength = previewLength
        self.wasSentOffDevice = wasSentOffDevice
    }
}

public struct NdaniFolderAccess: Sendable {
    public let url: URL
    public let didStartSecurityScope: Bool
    public let requiresSecurityScope: Bool

    public var isAvailable: Bool {
        requiresSecurityScope == false || didStartSecurityScope
    }

    public func stop() {
        if didStartSecurityScope {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

/// Downloads model packages to the local model directory.
/// Call `download(package:to:)` and observe `statuses[package.id]` for progress.
@MainActor
@Observable
public final class NdaniModelDownloader {
    public enum Status: Equatable, Sendable {
        case inProgress(fractionCompleted: Double)
        case done
        case failed(String)
    }

    public private(set) var statuses: [String: Status] = [:]

    public nonisolated init() {}

    /// Minimum free disk space required before starting a download (10 GB).
    private static let minimumFreeDiskBytes: Int64 = 10 * 1024 * 1024 * 1024

    public func download(
        package: NdaniLocalModelPackage,
        to directory: URL,
        session: URLSession = .shared
    ) async {
        guard let url = package.downloadURL else {
            statuses[package.id] = .failed("Setup is not available yet. The app can keep working without it.")
            return
        }

        // Pre-flight disk space check
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(
                forPath: (directory.path as NSString).deletingLastPathComponent
            )
            if let freeSize = attrs[.systemFreeSize] as? Int64,
               freeSize < Self.minimumFreeDiskBytes {
                let freeGB = Double(freeSize) / (1024 * 1024 * 1024)
                statuses[package.id] = .failed(
                    String(format: "Not enough disk space (%.1f GB free). At least 10 GB is needed.", freeGB)
                )
                return
            }
        } catch {
            // Non-fatal: proceed even if we can't check space
        }

        statuses[package.id] = .inProgress(fractionCompleted: 0)

        do {
            let (bytes, response) = try await session.bytes(from: url)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                statuses[package.id] = .failed("Setup could not finish. Check your connection and try again.")
                return
            }

            let expectedLength = http.expectedContentLength // -1 if unknown
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: tempURL)
            defer { try? handle.close() }

            var received: Int64 = 0
            let chunkSize = 256 * 1024 // 256 KB accumulation buffer
            var buffer = Data()
            buffer.reserveCapacity(chunkSize)

            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= chunkSize {
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)

                    if expectedLength > 0 {
                        let fraction = min(Double(received) / Double(expectedLength), 1.0)
                        statuses[package.id] = .inProgress(fractionCompleted: fraction)
                    }
                }
            }
            // Flush remaining bytes
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
            }
            try handle.close()

            statuses[package.id] = .inProgress(fractionCompleted: 1.0)

            if let expected = package.expectedSHA256 {
                guard let actual = NdaniDesktopState.sha256Hex(for: tempURL),
                      actual == expected.lowercased()
                else {
                    try? FileManager.default.removeItem(at: tempURL)
                    statuses[package.id] = .failed("Setup found a bad download and cleaned it up. Try again.")
                    return
                }
            }

            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(package.fileName)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            statuses[package.id] = .done
        } catch {
            statuses[package.id] = .failed("Setup was interrupted. Try again when the connection is stable.")
        }
    }

    public func reset(packageID: String) {
        statuses.removeValue(forKey: packageID)
    }
}

@MainActor
@Observable
public final class NdaniDesktopState {
    nonisolated public static let allowedFoldersStorageKey = "biz.nibiashara.ndani.desktop.allowedFolders"
    nonisolated public static let localReadLedgerStorageKey = "biz.nibiashara.ndani.desktop.localReadLedger"
    nonisolated public static let maxLocalReadLedgerEntries = 25

    public var selectedTier: NdaniModelTier
    public var localRuntimeEnabled: Bool
    public var hostedInferenceEnabled: Bool
    public var modelDirectory: URL
    public private(set) var modelStatuses: [NdaniLocalModelStatus]
    public private(set) var smokeTestResults: [String: NdaniSmokeTestResult]
    public private(set) var allowedFolders: [NdaniAllowedFolder]
    public private(set) var lastLocalReadResult: NdaniLocalReadResult?
    public private(set) var localReadLedger: [NdaniLocalReadLedgerEntry]
    public let modelDownloader: NdaniModelDownloader
    public let appUpdater: NdaniAppUpdater
    /// Override store directory for tests. Production code leaves this nil.
    let permissionStoreDirectory: URL?

    // Data Vault
    /// Opaque participant identifier issued by the configured rail.
    /// The app is free, so this is NOT a licence and buys nothing — it exists
    /// only so a rail can attribute a payout to the person who earned it.
    public var vaultParticipantID: String = ""
    public var vaultSelectedType: NdaniVaultDataType = .writingStyle
    public var vaultTitle: String = ""
    public var vaultSummary: String = ""
    public var vaultSubmitting: Bool = false
    public private(set) var vaultLastResult: NdaniVaultOfferResult?
    public private(set) var vaultErrorMessage: String?

    /// Optional account backend. Empty unless configured — see `NdaniBackendConfig`.
    static var backendBaseURL: String { NdaniBackendConfig.baseURL }
    public static var defaultModelDirectory: URL {
        #if os(iOS)
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("models", isDirectory: true)
        #else
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ndani", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        #endif
    }

    nonisolated public static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(iOS)
        return []
        #else
        return [.withSecurityScope]
        #endif
    }

    public init(
        selectedTier: NdaniModelTier = .desktop,
        localRuntimeEnabled: Bool = false,
        hostedInferenceEnabled: Bool = false,
        modelDirectory: URL = NdaniDesktopState.defaultModelDirectory,
        modelStatuses: [NdaniLocalModelStatus]? = nil,
        smokeTestResults: [String: NdaniSmokeTestResult] = [:],
        allowedFolders: [NdaniAllowedFolder] = [],
        lastLocalReadResult: NdaniLocalReadResult? = nil,
        localReadLedger: [NdaniLocalReadLedgerEntry] = [],
        permissionStoreDirectory: URL? = nil
    ) {
        self.selectedTier = selectedTier
        self.localRuntimeEnabled = localRuntimeEnabled
        self.hostedInferenceEnabled = hostedInferenceEnabled
        self.modelDirectory = modelDirectory
        self.modelStatuses = modelStatuses ?? Self.detectModels(in: modelDirectory)
        self.smokeTestResults = smokeTestResults
        self.allowedFolders = allowedFolders
        self.lastLocalReadResult = lastLocalReadResult
        self.localReadLedger = localReadLedger
        self.modelDownloader = NdaniModelDownloader()
        self.appUpdater = NdaniAppUpdater()
        self.permissionStoreDirectory = permissionStoreDirectory
    }

    public var privacyStatus: String {
        hostedInferenceEnabled ? "External model enabled by consent" : "No token inference configured"
    }

    public var allowedFolderCount: Int {
        allowedFolders.count
    }

    public var installedModelCount: Int {
        modelStatuses.filter(\.isInstalled).count
    }

    public var launchableModelCount: Int {
        modelStatuses.filter(\.canLaunchRuntime).count
    }

    public var modelStatusSummary: String {
        if launchableModelCount > 0 {
            "\(launchableModelCount) runtime-ready models"
        } else if installedModelCount > 0 {
            "\(installedModelCount) local models need checks"
        } else {
            "No local models found"
        }
    }

    public func refreshModelStatuses() {
        modelStatuses = Self.detectModels(in: modelDirectory)
    }

    public static func recommendedPackage(
        for tier: NdaniModelTier,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> NdaniLocalModelPackage? {
        NdaniLocalModelPackage.recommended.first {
            $0.tier == tier
                && $0.downloadURL != nil
                && $0.runtimeAdapter.hasInProcessLoader
                && $0.supportsDevice(physicalMemoryBytes: physicalMemoryBytes)
        } ?? NdaniLocalModelPackage.recommended.first {
            $0.tier == tier
                && $0.downloadURL != nil
                && $0.supportsDevice(physicalMemoryBytes: physicalMemoryBytes)
        } ?? NdaniLocalModelPackage.recommended.first {
            $0.tier == tier
                && $0.supportsDevice(physicalMemoryBytes: physicalMemoryBytes)
        }
    }

    public func recommendedPackage(for capability: NdaniPlatformCapability) -> NdaniLocalModelPackage? {
        guard let tier = capability.mode.recommendedTier else { return nil }
        return Self.recommendedPackage(for: tier, physicalMemoryBytes: capability.physicalMemoryBytes)
    }

    public func status(for package: NdaniLocalModelPackage) -> NdaniLocalModelStatus? {
        modelStatuses.first { $0.package.id == package.id }
    }

    public func preferredLaunchableModelStatus(
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> NdaniLocalModelStatus? {
        let supportedRecommendedIDs = NdaniLocalModelPackage.recommended
            .filter {
                $0.tier == selectedTier
                    && $0.runtimeAdapter.hasInProcessLoader
                    && $0.supportsDevice(physicalMemoryBytes: physicalMemoryBytes)
            }
            .map(\.id)

        for packageID in supportedRecommendedIDs {
            if let status = modelStatuses.first(where: { $0.package.id == packageID && $0.canLaunchRuntime }) {
                return status
            }
        }

        return modelStatuses.first {
            $0.canLaunchRuntime
                && $0.package.tier == selectedTier
                && $0.package.runtimeAdapter.hasInProcessLoader
                && $0.package.supportsDevice(physicalMemoryBytes: physicalMemoryBytes)
        } ?? modelStatuses.first {
            $0.canLaunchRuntime && $0.package.runtimeAdapter.hasInProcessLoader
        }
    }

    public func smokeTestResult(for status: NdaniLocalModelStatus) -> NdaniSmokeTestResult? {
        smokeTestResults[status.id]
    }

    public func runSmokeTest(for status: NdaniLocalModelStatus) {
        smokeTestResults[status.id] = Self.runLocalSmokeTest(for: status)
    }

    public func addAllowedFolder(displayName: String, path: String) {
        guard allowedFolders.contains(where: { $0.path == path }) == false else {
            return
        }
        allowedFolders.append(NdaniAllowedFolder(displayName: displayName, path: path))
    }

    public func addAllowedFolder(url: URL) throws {
        let bookmarkData = try Self.makeFolderBookmarkData(for: url)

        guard allowedFolders.contains(where: { $0.path == url.path }) == false else {
            return
        }

        allowedFolders.append(
            NdaniAllowedFolder(
                displayName: url.lastPathComponent,
                path: url.path,
                bookmarkData: bookmarkData
            )
        )
        NdaniPermissionStore.saveAllowedFolders(allowedFolders, storeDirectory: permissionStoreDirectory)
    }

    public func revokeAllowedFolder(id: NdaniAllowedFolder.ID) {
        allowedFolders.removeAll { $0.id == id }
        NdaniPermissionStore.saveAllowedFolders(allowedFolders, storeDirectory: permissionStoreDirectory)
    }

    public func revokeAllFolders() {
        allowedFolders.removeAll()
        NdaniPermissionStore.saveAllowedFolders(allowedFolders, storeDirectory: permissionStoreDirectory)
    }

    public func refreshSavedFolderAccess() {
        allowedFolders = Self.resolveAllowedFolders(allowedFolders)
        NdaniPermissionStore.saveAllowedFolders(allowedFolders, storeDirectory: permissionStoreDirectory)
    }

    /// Returns all readable text file contents from approved folders, for use as local AI context.
    public func readApprovedFolderContents() -> [(fileName: String, content: String)] {
        Self.readAllTextFiles(in: allowedFolders)
    }

    /// Whether any approved folder is accessible for file context.
    public var hasReadableFolders: Bool {
        allowedFolders.contains { !$0.isBookmarkStale }
    }

    public func readFirstTextFilePreview(now: Date = Date(), userDefaults: UserDefaults = .standard) {
        lastLocalReadResult = Self.readFirstTextFilePreview(in: allowedFolders)
        if let lastLocalReadResult {
            appendLocalReadLedgerEntry(
                Self.localReadLedgerEntry(from: lastLocalReadResult, timestamp: now)
            )
        }
    }

    public func appendLocalReadLedgerEntry(
        _ entry: NdaniLocalReadLedgerEntry,
        userDefaults: UserDefaults = .standard
    ) {
        localReadLedger.insert(entry, at: 0)
        localReadLedger = Array(localReadLedger.prefix(Self.maxLocalReadLedgerEntries))
        NdaniPermissionStore.saveLocalReadLedger(localReadLedger, storeDirectory: permissionStoreDirectory)
    }

    public func clearLocalReadLedger(userDefaults: UserDefaults = .standard) {
        localReadLedger.removeAll()
        NdaniPermissionStore.saveLocalReadLedger(localReadLedger, storeDirectory: permissionStoreDirectory)
    }

    /// Download a model package to the local model directory.
    @MainActor
    public func downloadModel(_ package: NdaniLocalModelPackage) {
        let downloader = modelDownloader
        let dir = modelDirectory
        Task { @MainActor in
            await downloader.download(package: package, to: dir)
            self.refreshModelStatuses()
        }
    }

    // MARK: Data Vault

    @MainActor
    public func submitVaultOffer() {
        vaultSubmitting = false
        vaultLastResult = nil
        vaultErrorMessage = "Unsigned legacy submissions are unavailable. Use signed per-offer consent."
    }

    public static func detectModels(
        in directory: URL,
        fileManager: FileManager = .default,
        runtimeRootDirectories: [URL] = defaultRuntimeRootDirectories(),
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> [NdaniLocalModelStatus] {
        NdaniLocalModelPackage.recommended.map { package in
            let url = directory.appendingPathComponent(package.fileName, isDirectory: false)
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let byteCount = attributes?[.size] as? Int64
            let readiness = runtimeReadiness(
                for: url,
                package: package,
                byteCount: byteCount,
                fileManager: fileManager,
                runtimeRootDirectories: runtimeRootDirectories,
                physicalMemoryBytes: physicalMemoryBytes
            )

            return NdaniLocalModelStatus(
                package: package,
                path: url.path,
                byteCount: byteCount,
                readiness: readiness
            )
        }
    }

    public static func runtimeReadiness(
        for url: URL,
        package: NdaniLocalModelPackage,
        byteCount: Int64?,
        fileManager: FileManager = .default,
        runtimeRootDirectories: [URL] = defaultRuntimeRootDirectories(),
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> NdaniRuntimeReadiness {
        guard let byteCount else {
            return .missing
        }

        guard fileManager.isReadableFile(atPath: url.path) else {
            return .blocked
        }

        guard package.runtimeAdapter.acceptsModelFile(url) else {
            return .formatMismatch
        }

        guard byteCount >= package.runtimeAdapter.minimumModelBytes else {
            return .invalid
        }

        if let expectedSHA256 = package.expectedSHA256,
           sha256Hex(for: url) != expectedSHA256.lowercased() {
            return .hashMismatch
        }

        guard package.supportsDevice(physicalMemoryBytes: physicalMemoryBytes) else {
            return .hardwareCheckRequired
        }

        guard package.runtimeAdapter.hasInProcessLoader else {
            return .loaderMissing
        }

        return .ready
    }

    public static func runLocalSmokeTest(
        for status: NdaniLocalModelStatus,
        prompt: String = "Reply with OK.",
        timeoutSeconds: TimeInterval = 8,
        runtimeRootDirectories: [URL] = defaultRuntimeRootDirectories(),
        maxOutputCharacters: Int = 240
    ) -> NdaniSmokeTestResult {
        guard status.canLaunchRuntime else {
            return .notReady
        }

        let url = URL(fileURLWithPath: status.path)
        let (valid, detail) = status.package.runtimeAdapter.validateModelFile(at: url)
        let capped = String(detail.prefix(maxOutputCharacters))

        if valid {
            return NdaniSmokeTestResult(status: .passed, detail: capped)
        } else {
            return NdaniSmokeTestResult(status: .failed, detail: capped)
        }
    }

    public static func makeFolderBookmarkData(for url: URL) throws -> Data {
        #if os(iOS)
        return try url.bookmarkData()
        #else
        return try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    nonisolated public static func resolveAllowedFolders(_ folders: [NdaniAllowedFolder]) -> [NdaniAllowedFolder] {
        folders.map { folder in
            guard let bookmarkData = folder.bookmarkData else {
                return folder
            }

            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: NdaniDesktopState.bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return NdaniAllowedFolder(
                    id: folder.id,
                    displayName: folder.displayName,
                    path: folder.path,
                    bookmarkData: bookmarkData,
                    isBookmarkStale: true
                )
            }

            return NdaniAllowedFolder(
                id: folder.id,
                displayName: url.lastPathComponent,
                path: url.path,
                bookmarkData: bookmarkData,
                isBookmarkStale: isStale
            )
        }
    }

    public static func saveAllowedFolders(
        _ folders: [NdaniAllowedFolder],
        storeDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        NdaniPermissionStore.saveAllowedFolders(folders, storeDirectory: storeDirectory)
    }

    public static func loadAllowedFolders(
        storeDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard
    ) -> [NdaniAllowedFolder] {
        NdaniPermissionStore.loadAllowedFolders(storeDirectory: storeDirectory, migrating: userDefaults)
    }

    public static func saveLocalReadLedger(
        _ ledger: [NdaniLocalReadLedgerEntry],
        storeDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        NdaniPermissionStore.saveLocalReadLedger(ledger, storeDirectory: storeDirectory)
    }

    public static func loadLocalReadLedger(
        storeDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard
    ) -> [NdaniLocalReadLedgerEntry] {
        NdaniPermissionStore.loadLocalReadLedger(storeDirectory: storeDirectory, migrating: userDefaults)
    }

    public static func localReadLedgerEntry(
        from result: NdaniLocalReadResult,
        timestamp: Date = Date()
    ) -> NdaniLocalReadLedgerEntry {
        NdaniLocalReadLedgerEntry(
            timestamp: timestamp,
            folderPath: result.folderPath,
            filePath: result.filePath,
            status: result.status,
            previewLength: result.preview?.count ?? 0,
            wasSentOffDevice: false
        )
    }

    public static func readFirstTextFilePreview(
        in folders: [NdaniAllowedFolder],
        fileManager: FileManager = .default
    ) -> NdaniLocalReadResult {
        guard let folder = folders.first else {
            return NdaniLocalReadResult(status: .noFolder, detail: "No approved folder is available.", preview: nil)
        }

        guard folder.isBookmarkStale == false else {
            return NdaniLocalReadResult(
                status: .stalePermission,
                detail: "Folder permission needs refresh.",
                preview: nil,
                folderPath: folder.path
            )
        }

        guard let access = startFolderAccess(for: folder) else {
            return NdaniLocalReadResult(
                status: .stalePermission,
                detail: "Folder permission needs refresh.",
                preview: nil,
                folderPath: folder.path
            )
        }
        defer { access.stop() }

        guard access.isAvailable else {
            return NdaniLocalReadResult(
                status: .accessDenied,
                detail: "Could not open approved folder permission.",
                preview: nil,
                folderPath: access.url.path
            )
        }

        guard let fileURL = firstTextFileURL(in: access.url, fileManager: fileManager) else {
            return NdaniLocalReadResult(
                status: .missingFile,
                detail: "No text file found in approved folder.",
                preview: nil,
                folderPath: access.url.path
            )
        }

        return readTextFilePreview(fileURL: fileURL, allowedFolder: folder, fileManager: fileManager)
    }

    public static func readTextFilePreview(
        fileURL: URL,
        allowedFolder folder: NdaniAllowedFolder,
        maxCharacters: Int = 500,
        fileManager: FileManager = .default
    ) -> NdaniLocalReadResult {
        guard folder.isBookmarkStale == false else {
            return NdaniLocalReadResult(
                status: .stalePermission,
                detail: "Folder permission needs refresh.",
                preview: nil,
                folderPath: folder.path,
                filePath: fileURL.path
            )
        }

        guard let access = startFolderAccess(for: folder) else {
            return NdaniLocalReadResult(
                status: .stalePermission,
                detail: "Folder permission needs refresh.",
                preview: nil,
                folderPath: folder.path,
                filePath: fileURL.path
            )
        }
        defer { access.stop() }

        guard access.isAvailable else {
            return NdaniLocalReadResult(
                status: .accessDenied,
                detail: "Could not open approved folder permission.",
                preview: nil,
                folderPath: access.url.path,
                filePath: fileURL.path
            )
        }

        guard isFile(fileURL, inside: access.url) else {
            return NdaniLocalReadResult(
                status: .outsideApprovedFolder,
                detail: "File is outside approved folder.",
                preview: nil,
                folderPath: access.url.path,
                filePath: fileURL.path
            )
        }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return NdaniLocalReadResult(
                status: .missingFile,
                detail: "Approved file does not exist.",
                preview: nil,
                folderPath: access.url.path,
                filePath: fileURL.path
            )
        }

        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return NdaniLocalReadResult(
                status: .unreadable,
                detail: "Could not read file as UTF-8 text.",
                preview: nil,
                folderPath: access.url.path,
                filePath: fileURL.path
            )
        }

        let preview = String(text.prefix(maxCharacters))
        return NdaniLocalReadResult(
            status: .ready,
            detail: fileURL.lastPathComponent,
            preview: preview,
            folderPath: access.url.path,
            filePath: fileURL.path
        )
    }

    public static func startFolderAccess(for folder: NdaniAllowedFolder) -> NdaniFolderAccess? {
        if let bookmarkData = folder.bookmarkData {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: NdaniDesktopState.bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), isStale == false else {
                return nil
            }

            let didStart = url.startAccessingSecurityScopedResource()
            return NdaniFolderAccess(url: url, didStartSecurityScope: didStart, requiresSecurityScope: true)
        }

        return NdaniFolderAccess(
            url: URL(fileURLWithPath: folder.path, isDirectory: true),
            didStartSecurityScope: false,
            requiresSecurityScope: false
        )
    }

    /// Reads all text files from all approved folders, returning an array of (fileName, content) pairs.
    /// Each file is capped at `maxCharsPerFile` characters. Total output is capped at `maxTotalChars`.
    public static func readAllTextFiles(
        in folders: [NdaniAllowedFolder],
        maxCharsPerFile: Int = 4000,
        maxTotalChars: Int = 16000,
        fileManager: FileManager = .default
    ) -> [(fileName: String, content: String)] {
        var results: [(fileName: String, content: String)] = []
        var totalChars = 0

        for folder in folders {
            guard !folder.isBookmarkStale,
                  let access = startFolderAccess(for: folder),
                  access.isAvailable
            else { continue }
            defer { access.stop() }

            guard let children = try? fileManager.contentsOfDirectory(
                at: access.url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let textFiles = children
                .filter { ["txt", "md", "csv", "json", "log"].contains($0.pathExtension.lowercased()) }
                .filter { isFile($0, inside: access.url) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            for fileURL in textFiles {
                guard totalChars < maxTotalChars else { break }
                guard let text = try? String(contentsOf: fileURL, encoding: .utf8), !text.isEmpty else { continue }
                let capped = String(text.prefix(min(maxCharsPerFile, maxTotalChars - totalChars)))
                results.append((fileName: fileURL.lastPathComponent, content: capped))
                totalChars += capped.count
            }

            guard totalChars < maxTotalChars else { break }
        }

        return results
    }

    public static func firstTextFileURL(in folderURL: URL, fileManager: FileManager = .default) -> URL? {
        guard let children = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return children
            .filter { ["txt", "md"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .first
    }

    public static func isFile(_ fileURL: URL, inside folderURL: URL) -> Bool {
        let filePath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        let folderPath = folderURL.resolvingSymlinksInPath().standardizedFileURL.path
        return filePath == folderPath || filePath.hasPrefix(folderPath + "/")
    }

    public static func defaultRuntimeRootDirectories() -> [URL] {
        #if os(iOS)
        return [
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("runtimes", isDirectory: true)
        ]
        #else
        return [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ndani", isDirectory: true)
                .appendingPathComponent("runtimes", isDirectory: true),
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("Ndani", isDirectory: true)
                .appendingPathComponent("Runtimes", isDirectory: true),
        ]
        .compactMap { $0 }
        #endif
    }

    public static func canRunWorkstationClassModel(
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> Bool {
        physicalMemoryBytes >= 32 * 1024 * 1024 * 1024
    }

    public static func sha256Hex(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let chunkSize = 8 * 1024 * 1024 // 8 MB
        var hasher = SHA256()

        while autoreleasepool(invoking: {
            guard let chunk = try? handle.read(upToCount: chunkSize),
                  !chunk.isEmpty else {
                return false
            }
            hasher.update(data: chunk)
            return true
        }) {}

        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct NdaniAllowedFolderRecord: Codable {
    let id: UUID
    let displayName: String
    let path: String
    let bookmarkData: Data?
    let isBookmarkStale: Bool

    init(folder: NdaniAllowedFolder) {
        id = folder.id
        displayName = folder.displayName
        path = folder.path
        bookmarkData = folder.bookmarkData
        isBookmarkStale = folder.isBookmarkStale
    }

    var folder: NdaniAllowedFolder {
        NdaniAllowedFolder(
            id: id,
            displayName: displayName,
            path: path,
            bookmarkData: bookmarkData,
            isBookmarkStale: isBookmarkStale
        )
    }
}

struct NdaniLocalReadLedgerRecord: Codable {
    let id: UUID
    let timestamp: Date
    let folderPath: String?
    let filePath: String?
    let status: NdaniLocalReadStatus
    let previewLength: Int
    let wasSentOffDevice: Bool

    init(entry: NdaniLocalReadLedgerEntry) {
        id = entry.id
        timestamp = entry.timestamp
        folderPath = entry.folderPath
        filePath = entry.filePath
        status = entry.status
        previewLength = entry.previewLength
        wasSentOffDevice = entry.wasSentOffDevice
    }

    var entry: NdaniLocalReadLedgerEntry {
        NdaniLocalReadLedgerEntry(
            id: id,
            timestamp: timestamp,
            folderPath: folderPath,
            filePath: filePath,
            status: status,
            previewLength: previewLength,
            wasSentOffDevice: wasSentOffDevice
        )
    }
}

// MARK: - Data Vault

/// Categories of self-written summary a user can voluntarily offer.
/// Not anonymous: a submission is linked to the participant id that sent it.
public enum NdaniVaultDataType: String, CaseIterable, Sendable, Identifiable {
    case writingStyle   = "writing-style"
    case topicInterests = "topic-interests"
    case workPatterns   = "work-patterns"
    case languageUse    = "language-use"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .writingStyle:   "Writing style"
        case .topicInterests: "Topic interests"
        case .workPatterns:   "Work patterns"
        case .languageUse:    "Language use"
        }
    }

    public var placeholder: String {
        switch self {
        case .writingStyle:
            "e.g. Tend to write short paragraphs, prefer plain language, avoid jargon."
        case .topicInterests:
            "e.g. Interested in small business finance, East African trade, local logistics."
        case .workPatterns:
            "e.g. Write most in the morning, usually working on proposals and supplier lists."
        case .languageUse:
            "e.g. Mix Swahili and English, use formal register for client emails."
        }
    }
}

public struct NdaniVaultOfferResult: Sendable {
    public let offerID: String
    public let creditCode: String
    public let creditAmountUSD: Double
    public let message: String
}

// MARK: - Offers Marketplace

/// A buyer offer from the marketplace. Users browse, accept, and submit summaries.
public struct NdaniBuyerOffer: Identifiable, Sendable {
    public let id: String
    public let buyer: String
    public let buyerVerified: Bool
    public let title: String
    public let description: String
    public let dataType: String
    public let payoutUSD: Double
    public let spotsLeft: Int
    public let tags: [String]
    public let expiresAt: String
}

/// Result of submitting a user summary for a buyer offer.
public struct NdaniOfferSubmissionResult: Sendable {
    public let submissionID: String
    public let offerID: String
    public let payoutUSD: Double
    public let message: String
}

/// User's balance and earnings summary.
public struct NdaniUserBalance: Sendable {
    public let balanceUSD: Double
    public let totalEarnedUSD: Double
    public let totalPaidOutUSD: Double
    public let canWithdraw: Bool
    public let stripeConnected: Bool
}

/// Marketplace client — fetches offers, submits summaries, checks balance.
@MainActor
@Observable
public final class NdaniMarketplace {
    public private(set) var availableOffers: [NdaniBuyerOffer] = []
    public private(set) var balance: NdaniUserBalance?
    public private(set) var isLoading = false
    public private(set) var lastError: String?
    public private(set) var lastSubmission: NdaniOfferSubmissionResult?
    public private(set) var lastConsentSubmissionID: String?

    private let backendBase: String

    /// `nil` when no account backend is configured, which disables hosted features.
    private func backendURL(_ path: String) -> URL? {
        guard !backendBase.isEmpty else { return nil }
        return URL(string: backendBase + path)
    }

    public init(backendBase: String = NdaniBackendConfig.baseURL) {
        self.backendBase = backendBase
    }

    public func fetchOffers(session: URLSession = .shared) async {
        availableOffers = []
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        guard let url = backendURL("/api/offers/available") else {
            lastError = NdaniBackendConfig.notConfiguredMessage
            return
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw NdaniConsentSaleError.invalidOffer }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let offers = json?["offers"] as? [[String: Any]] else { return }
            availableOffers = try offers.map { raw in
                let o = try NdaniOfferSchema.normalize(raw)
                guard let id = o["id"] as? String,
                      let buyer = o["buyer"] as? String,
                      let title = o["title"] as? String,
                      let desc = o["description"] as? String,
                      let payout = o["payout_usd"] as? Double else { throw NdaniConsentSaleError.invalidOffer }
                return NdaniBuyerOffer(
                    id: id, buyer: buyer,
                    buyerVerified: o["buyer_verified"] as? Bool ?? false,
                    title: title, description: desc,
                    dataType: o["data_type"] as? String ?? "",
                    payoutUSD: payout,
                    spotsLeft: o["spots_left"] as? Int ?? 0,
                    tags: o["tags"] as? [String] ?? [],
                    expiresAt: o["expires_at"] as? String ?? ""
                )
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func submit(
        participantID: String,
        offerID: String,
        dataType: String,
        title: String,
        summary: String,
        consentEnvelope: NdaniConsentEnvelope? = nil,
        session: URLSession = .shared
    ) async {
        isLoading = true
        lastError = nil
        lastSubmission = nil
        lastConsentSubmissionID = nil
        defer { isLoading = false }

        guard (1...1200).contains(summary.unicodeScalars.count) else {
            lastError = "Write a summary of 1–1200 characters."; return
        }
        guard let consentEnvelope, consentEnvelope.matches(participantID: participantID, offerID: offerID, summary: summary) else {
            lastError = "A signed per-offer consent is required; sales remain unavailable."; return
        }
        guard let url = backendURL("/api/consent-sale/submit") else {
            lastError = NdaniBackendConfig.notConfiguredMessage
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = consentEnvelope.json
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(json.keys) == Set(["submission_id", "request_sha256", "status", "payout_status", "contributor_obligation_cents", "withdrawal_available"]),
                  let sid = json["submission_id"] as? String, sid.count == 64,
                  sid.allSatisfy({ "0123456789abcdef".contains($0) }),
                  json["request_sha256"] as? String == consentEnvelope.requestSHA256,
                  json["status"] as? String == "consented",
                  json["payout_status"] as? String == "unverified",
                  json["contributor_obligation_cents"] is NSNull,
                  let withdrawal = json["withdrawal_available"] as? NSNumber,
                  CFGetTypeID(withdrawal) == CFBooleanGetTypeID(), !withdrawal.boolValue else {
                lastError = "Submission held; no verified consent acceptance response."
                return
            }
            lastConsentSubmissionID = sid
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func fetchBalance(participantID: String, signature: String, session: URLSession = .shared) async {
        balance = nil
        guard let url = backendURL("/api/balance?participant=\(participantID)&sig=\(signature)") else {
            lastError = NdaniBackendConfig.notConfiguredMessage
            return
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw NdaniConsentSaleError.invalidOffer }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let cash = json?["balance_usd"] as? Double, cash.isFinite, cash >= 0,
                  let earned = json?["total_earned_usd"] as? Double, earned.isFinite, earned >= 0,
                  let paid = json?["total_paid_out_usd"] as? Double, paid.isFinite, paid >= 0 else {
                balance = nil
                lastError = "Balance is unverified; missing money is not zero."
                return
            }
            balance = NdaniUserBalance(
                balanceUSD: cash,
                totalEarnedUSD: earned,
                totalPaidOutUSD: paid,
                canWithdraw: json?["can_withdraw"] as? Bool ?? false,
                stripeConnected: json?["stripe_connected"] as? Bool ?? false
            )
        } catch {
            lastError = error.localizedDescription
        }
    }
}

// MARK: - On-demand App Updater

/// Metadata returned by the backend update manifest endpoint.
public struct NdaniAppUpdateInfo: Sendable {
    public let version: String
    public let releaseNotes: String
    public let downloadURL: URL
    public let releasedAt: String
    public let minMacOS: String
}

/// User-triggered update checker. Never polls in the background.
/// Call `checkForUpdate()` only in response to an explicit user action.
@MainActor
@Observable
public final class NdaniAppUpdater {
    /// The version bundled with the currently running app.
    public static let currentVersion = "0.4.0"

    public private(set) var isChecking: Bool = false
    public private(set) var updateInfo: NdaniAppUpdateInfo?
    public private(set) var checkError: String?

    /// True when the manifest returns a version different from the running build.
    public var hasUpdate: Bool {
        guard let info = updateInfo else { return false }
        return info.version != Self.currentVersion
    }

    public nonisolated init() {}

    /// Fetch the update manifest from the backend. User must initiate this call — never automatic.
    public func checkForUpdate() {
        guard !isChecking else { return }
        isChecking = true
        checkError = nil
        Task { @MainActor in
            defer { isChecking = false }
            do {
                guard let url = NdaniBackendConfig.url("/api/updates/latest") else {
                    checkError = NdaniBackendConfig.isConfigured
                        ? "Invalid update URL."
                        : NdaniBackendConfig.notConfiguredMessage
                    return
                }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    checkError = "Update check failed."
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let version = json["version"] as? String,
                      let notes = json["release_notes"] as? String,
                      let dlString = json["download_url"] as? String,
                      let dlURL = URL(string: dlString),
                      let releasedAt = json["released_at"] as? String,
                      let minMacOS = json["min_macos"] as? String
                else {
                    checkError = "Could not read update manifest."
                    return
                }
                updateInfo = NdaniAppUpdateInfo(
                    version: version,
                    releaseNotes: notes,
                    downloadURL: dlURL,
                    releasedAt: releasedAt,
                    minMacOS: minMacOS
                )
            } catch {
                checkError = error.localizedDescription
            }
        }
    }
}

// MARK: - File-based persistence for folder permissions and read ledger.
/// File-based persistence for folder permissions and read ledger.
/// Stores JSON in ~/Library/Application Support/Ndani/ by default.
/// Pass `storeDirectory:` to override (used in tests).
/// Migrates from UserDefaults on first load if no file store exists yet.
public enum NdaniPermissionStore {
    static func resolvedDirectory(_ override: URL?) -> URL? {
        override ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Ndani", isDirectory: true)
    }

    public static func saveAllowedFolders(_ folders: [NdaniAllowedFolder], storeDirectory: URL? = nil) {
        guard let dir = resolvedDirectory(storeDirectory) else { return }
        let records = folders.map(NdaniAllowedFolderRecord.init(folder:))
        guard let data = try? JSONEncoder().encode(records) else { return }
        NdaniPrivateFileStore.writePrivateData(data, to: dir.appendingPathComponent("allowed-folders.json"))
    }

    public static func loadAllowedFolders(
        storeDirectory: URL? = nil,
        migrating defaults: UserDefaults = .standard
    ) -> [NdaniAllowedFolder] {
        if let dir = resolvedDirectory(storeDirectory) {
            let url = dir.appendingPathComponent("allowed-folders.json")
            if let data = NdaniPrivateFileStore.readPrivateDataMigrating(from: url),
               let records = try? JSONDecoder().decode([NdaniAllowedFolderRecord].self, from: data) {
                return NdaniDesktopState.resolveAllowedFolders(records.map(\.folder))
            }
        }
        // Migrate from UserDefaults on first launch
        guard let data = defaults.data(forKey: NdaniDesktopState.allowedFoldersStorageKey),
              let records = try? JSONDecoder().decode([NdaniAllowedFolderRecord].self, from: data)
        else { return [] }
        let folders = NdaniDesktopState.resolveAllowedFolders(records.map(\.folder))
        saveAllowedFolders(folders, storeDirectory: storeDirectory)
        defaults.removeObject(forKey: NdaniDesktopState.allowedFoldersStorageKey)
        return folders
    }

    public static func saveLocalReadLedger(_ ledger: [NdaniLocalReadLedgerEntry], storeDirectory: URL? = nil) {
        guard let dir = resolvedDirectory(storeDirectory) else { return }
        let records = ledger.map(NdaniLocalReadLedgerRecord.init(entry:))
        guard let data = try? JSONEncoder().encode(records) else { return }
        NdaniPrivateFileStore.writePrivateData(data, to: dir.appendingPathComponent("read-ledger.json"))
    }

    public static func loadLocalReadLedger(
        storeDirectory: URL? = nil,
        migrating defaults: UserDefaults = .standard
    ) -> [NdaniLocalReadLedgerEntry] {
        if let dir = resolvedDirectory(storeDirectory) {
            let url = dir.appendingPathComponent("read-ledger.json")
            if let data = NdaniPrivateFileStore.readPrivateDataMigrating(from: url),
               let records = try? JSONDecoder().decode([NdaniLocalReadLedgerRecord].self, from: data) {
                return records.map(\.entry)
            }
        }
        // Migrate from UserDefaults on first launch
        guard let data = defaults.data(forKey: NdaniDesktopState.localReadLedgerStorageKey),
              let records = try? JSONDecoder().decode([NdaniLocalReadLedgerRecord].self, from: data)
        else { return [] }
        let entries = records.map(\.entry)
        saveLocalReadLedger(entries, storeDirectory: storeDirectory)
        defaults.removeObject(forKey: NdaniDesktopState.localReadLedgerStorageKey)
        return entries
    }
}
