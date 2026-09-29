import Foundation
import Testing
@testable import AppCore

@MainActor
struct StarterAppStateTests {
    @Test
    func defaultStateUsesDesktopTier() {
        #expect(NdaniDesktopState().selectedTier == .desktop)
    }

    @Test
    func conversationalRecommendationsExcludeToyModels() {
        #expect(NdaniLocalModelPackage.recommended.contains { $0.id.contains("135m") } == false)
        #expect(NdaniLocalModelPackage.recommended.contains { $0.title.lowercased().contains("smollm") } == false)
    }

    @Test
    func defaultStateHasNoTokenInference() {
        #expect(NdaniDesktopState().privacyStatus == "No token inference configured")
    }

    @Test
    func modelDetectionFindsInstalledPackage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let package = try #require(NdaniLocalModelPackage.recommended.first { $0.id == "qwen3-4b-gguf" })
        let packageURL = directory.appendingPathComponent(package.fileName)
        var data = Data([0x47, 0x47, 0x55, 0x46])
        data.append(Data(repeating: 0, count: 100))
        try data.write(to: packageURL)

        let statuses = NdaniDesktopState.detectModels(in: directory, runtimeRootDirectories: [directory])
        let installed = statuses.first { $0.package.id == package.id }

        #expect(installed?.isInstalled == true)
        #expect(installed?.readiness == .ready)
    }

    @Test
    func emptyModelPackageNeedsValidPackage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let package = try #require(NdaniLocalModelPackage.recommended.first { $0.id == "qwen3-4b-gguf" })
        let packageURL = directory.appendingPathComponent(package.fileName)
        try Data().write(to: packageURL)

        let statuses = NdaniDesktopState.detectModels(in: directory, runtimeRootDirectories: [directory])
        let installed = statuses.first { $0.package.id == package.id }

        #expect(installed?.isInstalled == true)
        #expect(installed?.readiness == .invalid)
        #expect(installed?.canLaunchRuntime == false)
    }

    @Test
    func modelPackageWithValidFileIsReady() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let package = try #require(NdaniLocalModelPackage.recommended.first { $0.id == "qwen3-4b-gguf" })
        let packageURL = directory.appendingPathComponent(package.fileName)
        // Write valid GGUF header
        var data = Data([0x47, 0x47, 0x55, 0x46]) // "GGUF" magic
        data.append(Data(repeating: 0, count: 100))
        try data.write(to: packageURL)

        let statuses = NdaniDesktopState.detectModels(in: directory, runtimeRootDirectories: [directory])
        let installed = statuses.first { $0.package.id == package.id }

        #expect(installed?.isInstalled == true)
        #expect(installed?.readiness == .ready)
        #expect(installed?.canLaunchRuntime == true)
    }

    @Test
    func modelWithValidFileButNoExecutableIsStillReady() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let package = try #require(NdaniLocalModelPackage.recommended.first { $0.id == "qwen3-4b-gguf" })
        var data = Data([0x47, 0x47, 0x55, 0x46])
        data.append(Data(repeating: 0, count: 100))
        try data.write(to: directory.appendingPathComponent(package.fileName))

        let status = try #require(
            NdaniDesktopState.detectModels(in: directory, runtimeRootDirectories: [directory])
                .first { $0.package.id == package.id }
        )

        // No external executable required — sandbox-safe validation
        #expect(status.readiness == .ready)
    }

    @Test
    func phoneRecommendationDoesNotUseFourBAsHumanFloor() throws {
        let noBaselinePackage = NdaniDesktopState.recommendedPackage(
            for: .phone,
            physicalMemoryBytes: 6 * 1024 * 1024 * 1024
        )

        #expect(noBaselinePackage?.id == "qwen3-4b-gguf")
        #expect(noBaselinePackage?.detail.localizedCaseInsensitiveContains("Not the human conversation baseline") == true)
    }

    @Test
    func iPhoneConversationBaselineUsesEightBClassFloor() throws {
        let package = try #require(
            NdaniDesktopState.recommendedPackage(
                for: .desktop,
                physicalMemoryBytes: 8 * 1024 * 1024 * 1024
            )
        )

        #expect(package.id == "qwen3-8b-gguf")
        #expect(package.runtimeAdapter.hasInProcessLoader == true)
    }

    @Test
    func phoneRecommendationRequiresEnoughMemoryForLiteModel() {
        let package = NdaniDesktopState.recommendedPackage(
            for: .phone,
            physicalMemoryBytes: 4 * 1024 * 1024 * 1024
        )

        #expect(package == nil)
    }

    @Test
    func downloadableModelPackagesUseHTTPS() throws {
        let urls = NdaniLocalModelPackage.recommended.compactMap(\.downloadURL)

        #expect(urls.isEmpty == false)
        #expect(urls.allSatisfy { $0.scheme == "https" })
    }

    @Test
    func laptopDesktopRecommendationUsesFourteenBLargeWhenMemoryAllows() throws {
        let package = try #require(
            NdaniDesktopState.recommendedPackage(
                for: .desktop,
                physicalMemoryBytes: 16 * 1024 * 1024 * 1024
            )
        )

        #expect(package.id == "qwen3-14b-gguf")
        #expect(package.title.contains("14B"))
        #expect(package.runtimeAdapter.hasInProcessLoader == true)
    }

    @Test
    func lowMemoryLaptopDesktopFallsBackToEightBStandard() throws {
        let package = try #require(
            NdaniDesktopState.recommendedPackage(
                for: .desktop,
                physicalMemoryBytes: 8 * 1024 * 1024 * 1024
            )
        )

        #expect(package.id == "qwen3-8b-gguf")
        #expect(package.title.contains("8B"))
    }

    @Test
    func preferredLaunchableModelUsesSelectedTierBeforeEarlierPhonePackage() throws {
        let phoneStatus = NdaniLocalModelStatus(
            package: try #require(NdaniLocalModelPackage.recommended.first { $0.id == "qwen3-4b-gguf" }),
            path: "/tmp/qwen3-4b.gguf",
            byteCount: 10,
            readiness: .ready
        )
        let largeStatus = NdaniLocalModelStatus(
            package: try #require(NdaniLocalModelPackage.recommended.first { $0.id == "qwen3-14b-gguf" }),
            path: "/tmp/qwen3-14b.gguf",
            byteCount: 10,
            readiness: .ready
        )
        let state = NdaniDesktopState(
            selectedTier: .desktop,
            modelStatuses: [phoneStatus, largeStatus]
        )

        let preferred = try #require(
            state.preferredLaunchableModelStatus(
                physicalMemoryBytes: 16 * 1024 * 1024 * 1024
            )
        )

        #expect(preferred.package.id == "qwen3-14b-gguf")
    }

    @Test
    func preferredLaunchableModelFallsBackFromLargeToEightBOnLowMemoryLaptop() throws {
        let largeStatus = NdaniLocalModelStatus(
            package: try #require(NdaniLocalModelPackage.recommended.first { $0.id == "qwen3-14b-gguf" }),
            path: "/tmp/qwen3-14b.gguf",
            byteCount: 10,
            readiness: .ready
        )
        let standardStatus = NdaniLocalModelStatus(
            package: try #require(NdaniLocalModelPackage.recommended.first { $0.id == "qwen3-8b-gguf" }),
            path: "/tmp/qwen3-8b.gguf",
            byteCount: 10,
            readiness: .ready
        )
        let state = NdaniDesktopState(
            selectedTier: .desktop,
            modelStatuses: [largeStatus, standardStatus]
        )

        let preferred = try #require(
            state.preferredLaunchableModelStatus(
                physicalMemoryBytes: 8 * 1024 * 1024 * 1024
            )
        )

        #expect(preferred.package.id == "qwen3-8b-gguf")
    }

    @Test
    func runtimeReadinessRejectsWrongModelExtension() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let package = NdaniLocalModelPackage(
            id: "wrong-format",
            title: "Wrong Format",
            fileName: "wrong-format.bin",
            tier: .desktop,
            detail: "Wrong format test.",
            runtimeAdapter: .liteRTLM,
            expectedSHA256: nil,
            downloadURL: nil
        )
        let modelURL = directory.appendingPathComponent(package.fileName)
        try Data("local model placeholder".utf8).write(to: modelURL)

        let readiness = NdaniDesktopState.runtimeReadiness(
            for: modelURL,
            package: package,
            byteCount: 10,
            runtimeRootDirectories: [directory]
        )

        #expect(readiness == .formatMismatch)
    }

    @Test
    func runtimeReadinessRejectsHashMismatchWhenHashIsPinned() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let package = NdaniLocalModelPackage(
            id: "hash-pinned",
            title: "Hash Pinned",
            fileName: "hash-pinned.litertlm",
            tier: .desktop,
            detail: "Hash test.",
            runtimeAdapter: .liteRTLM,
            expectedSHA256: String(repeating: "0", count: 64),
            downloadURL: nil
        )
        let modelURL = directory.appendingPathComponent(package.fileName)
        try Data("local model placeholder".utf8).write(to: modelURL)

        let readiness = NdaniDesktopState.runtimeReadiness(
            for: modelURL,
            package: package,
            byteCount: 10,
            runtimeRootDirectories: [directory]
        )

        #expect(readiness == .hashMismatch)
    }

    @Test
    func runtimeReadinessReportsHardwareCheckForWorkstationModel() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let package = try #require(NdaniLocalModelPackage.recommended.first { $0.id == "gemma-4-26b-a4b" })
        let modelURL = directory.appendingPathComponent(package.fileName)
        try Data("local model placeholder".utf8).write(to: modelURL)

        let readiness = NdaniDesktopState.runtimeReadiness(
            for: modelURL,
            package: package,
            byteCount: 10,
            runtimeRootDirectories: [directory],
            physicalMemoryBytes: 8 * 1024 * 1024 * 1024
        )

        #expect(readiness == .hardwareCheckRequired)
    }

    @Test
    func runtimeReadinessReportsHardwareCheckForLargeDesktopModelOnLowMemoryDevice() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let package = try #require(NdaniLocalModelPackage.recommended.first { $0.id == "qwen3-14b-gguf" })
        let modelURL = directory.appendingPathComponent(package.fileName)
        var data = Data([0x47, 0x47, 0x55, 0x46])
        data.append(Data(repeating: 0, count: 100))
        try data.write(to: modelURL)

        let lowMemoryReadiness = NdaniDesktopState.runtimeReadiness(
            for: modelURL,
            package: package,
            byteCount: Int64(data.count),
            runtimeRootDirectories: [directory],
            physicalMemoryBytes: 8 * 1024 * 1024 * 1024
        )
        let enoughMemoryReadiness = NdaniDesktopState.runtimeReadiness(
            for: modelURL,
            package: package,
            byteCount: Int64(data.count),
            runtimeRootDirectories: [directory],
            physicalMemoryBytes: 16 * 1024 * 1024 * 1024
        )

        #expect(lowMemoryReadiness == .hardwareCheckRequired)
        #expect(enoughMemoryReadiness == .ready)
    }

    @Test
    func runtimeAdapterBuildsArgumentsExactly() {
        #expect(
            NdaniLocalRuntimeAdapter.liteRTLM.smokeTestArguments(modelPath: "/models/a.litertlm", prompt: "Hi") ==
                ["--model", "/models/a.litertlm", "--prompt", "Hi", "--max-tokens", "8"]
        )
        #expect(
            NdaniLocalRuntimeAdapter.llamaCpp.smokeTestArguments(modelPath: "/models/a.gguf", prompt: "Hi") ==
                ["-m", "/models/a.gguf", "-p", "Hi", "-n", "8"]
        )
    }

    @Test
    func modelSummaryPrefersRuntimeReadyPackages() throws {
        let readyStatus = NdaniLocalModelStatus(
            package: try #require(NdaniLocalModelPackage.recommended.first { $0.id == "qwen3-4b-gguf" }),
            path: "/tmp/qwen3-4b.gguf",
            byteCount: 10,
            readiness: .ready
        )
        let invalidStatus = NdaniLocalModelStatus(
            package: try #require(NdaniLocalModelPackage.recommended.first { $0.id == "gemma-4-e2b-it" }),
            path: "/tmp/gemma-4-e2b-it.litertlm",
            byteCount: 0,
            readiness: .invalid
        )
        let state = NdaniDesktopState(modelStatuses: [readyStatus, invalidStatus])

        #expect(state.modelStatusSummary == "1 runtime-ready models")
    }

    @Test
    func localSmokeTestDoesNotRunForLiteRTWithoutBundledLoader() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let package = try #require(NdaniLocalModelPackage.recommended.first { $0.id == "gemma-4-e2b-it" })
        let packageURL = directory.appendingPathComponent(package.fileName)
        try Data("local model placeholder".utf8).write(to: packageURL)

        let status = try #require(
            NdaniDesktopState
                .detectModels(in: directory, runtimeRootDirectories: [directory])
                .first { $0.package.id == package.id }
        )
        let result = NdaniDesktopState.runLocalSmokeTest(for: status, runtimeRootDirectories: [directory])

        #expect(status.readiness == .loaderMissing)
        #expect(result == .notReady)
    }

    @Test
    func localSmokeTestPassesForValidGGUFModel() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let package = try #require(NdaniLocalModelPackage.recommended.first { $0.id == "qwen3-4b-gguf" })
        let packageURL = directory.appendingPathComponent(package.fileName)
        var data = Data([0x47, 0x47, 0x55, 0x46]) // GGUF magic
        data.append(Data(repeating: 0, count: 100))
        try data.write(to: packageURL)

        let status = try #require(
            NdaniDesktopState
                .detectModels(in: directory, runtimeRootDirectories: [directory])
                .first { $0.package.id == package.id }
        )
        let result = NdaniDesktopState.runLocalSmokeTest(for: status, runtimeRootDirectories: [directory])

        #expect(result.status == .passed)
        #expect(result.detail.contains("Valid GGUF"))
    }

    @Test
    func localSmokeTestFailsForInvalidGGUFHeader() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let package = try #require(NdaniLocalModelPackage.recommended.first { $0.id == "qwen3-4b-gguf" })
        let packageURL = directory.appendingPathComponent(package.fileName)
        try Data("not a gguf file content".utf8).write(to: packageURL)

        let status = try #require(
            NdaniDesktopState
                .detectModels(in: directory, runtimeRootDirectories: [directory])
                .first { $0.package.id == package.id }
        )
        let result = NdaniDesktopState.runLocalSmokeTest(for: status, runtimeRootDirectories: [directory])

        #expect(result.status == .failed)
        #expect(result.detail.contains("Not a valid GGUF"))
    }

    @Test
    func localSmokeTestCapsOutput() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let package = try #require(NdaniLocalModelPackage.recommended.first { $0.id == "qwen3-4b-gguf" })
        var data = Data([0x47, 0x47, 0x55, 0x46])
        data.append(Data(repeating: 0, count: 100))
        try data.write(to: directory.appendingPathComponent(package.fileName))

        let status = try #require(
            NdaniDesktopState.detectModels(in: directory, runtimeRootDirectories: [directory])
                .first { $0.package.id == package.id }
        )

        let result = NdaniDesktopState.runLocalSmokeTest(
            for: status,
            runtimeRootDirectories: [directory],
            maxOutputCharacters: 8
        )

        #expect(result.status == .passed)
        #expect(result.detail.count <= 8)
    }

    @Test
    func localSmokeTestDoesNotRunForUnreadyPackage() {
        let status = NdaniLocalModelStatus(
            package: NdaniLocalModelPackage.recommended[0],
            path: "/tmp/missing.litertlm",
            byteCount: nil,
            readiness: .missing
        )

        let result = NdaniDesktopState.runLocalSmokeTest(for: status, runtimeRootDirectories: [])

        #expect(result == .notReady)
    }

    @Test
    func allowedFoldersPersistThroughFileStore() throws {
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let folder = NdaniAllowedFolder(
            displayName: "Private",
            path: "/Users/example/Private",
            bookmarkData: Data("bookmark".utf8)
        )

        NdaniDesktopState.saveAllowedFolders([folder], storeDirectory: storeDir)
        let loaded = NdaniDesktopState.loadAllowedFolders(storeDirectory: storeDir)

        #expect(loaded.count == 1)
        #expect(loaded.first?.displayName == "Private")
        #expect(loaded.first?.path == "/Users/example/Private")
        #expect(loaded.first?.bookmarkData == Data("bookmark".utf8))
    }

    @Test
    func unresolvedBookmarkIsMarkedStale() {
        let folder = NdaniAllowedFolder(
            displayName: "Private",
            path: "/Users/example/Private",
            bookmarkData: Data("not a real bookmark".utf8)
        )

        let resolved = NdaniDesktopState.resolveAllowedFolders([folder])

        #expect(resolved.first?.isBookmarkStale == true)
    }

    @Test
    func localReadReturnsPreviewInsideApprovedFolder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = directory.appendingPathComponent("note.md")
        try Data("private local note".utf8).write(to: fileURL)
        let folder = NdaniAllowedFolder(displayName: "Private", path: directory.path)

        let result = NdaniDesktopState.readTextFilePreview(fileURL: fileURL, allowedFolder: folder)

        #expect(result.status == .ready)
        #expect(result.preview == "private local note")
    }

    @Test
    func localReadBlocksOutsideApprovedFolder() throws {
        let approved = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: approved, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: approved)
            try? FileManager.default.removeItem(at: outside)
        }

        let outsideFile = outside.appendingPathComponent("note.md")
        try Data("outside".utf8).write(to: outsideFile)
        let folder = NdaniAllowedFolder(displayName: "Private", path: approved.path)

        let result = NdaniDesktopState.readTextFilePreview(fileURL: outsideFile, allowedFolder: folder)

        #expect(result.status == .outsideApprovedFolder)
        #expect(result.preview == nil)
    }

    @Test
    func localReadBlocksStalePermission() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = directory.appendingPathComponent("note.md")
        try Data("private local note".utf8).write(to: fileURL)
        let folder = NdaniAllowedFolder(
            displayName: "Private",
            path: directory.path,
            isBookmarkStale: true
        )

        let result = NdaniDesktopState.readTextFilePreview(fileURL: fileURL, allowedFolder: folder)

        #expect(result.status == .stalePermission)
        #expect(result.preview == nil)
    }

    @Test
    func localReadBlocksUnresolvedBookmark() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = directory.appendingPathComponent("note.md")
        try Data("private local note".utf8).write(to: fileURL)
        let folder = NdaniAllowedFolder(
            displayName: "Private",
            path: directory.path,
            bookmarkData: Data("not a real bookmark".utf8)
        )

        let result = NdaniDesktopState.readTextFilePreview(fileURL: fileURL, allowedFolder: folder)

        #expect(result.status == .stalePermission)
        #expect(result.preview == nil)
    }

    @Test
    func localReadBlocksSymlinkOutsideApprovedFolder() throws {
        let approved = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: approved, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: approved)
            try? FileManager.default.removeItem(at: outside)
        }

        let outsideFile = outside.appendingPathComponent("secret.md")
        try Data("outside secret".utf8).write(to: outsideFile)
        let linkURL = approved.appendingPathComponent("linked.md")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: outsideFile)
        let folder = NdaniAllowedFolder(displayName: "Private", path: approved.path)

        let result = NdaniDesktopState.readTextFilePreview(fileURL: linkURL, allowedFolder: folder)

        #expect(result.status == .outsideApprovedFolder)
        #expect(result.preview == nil)
    }

    @Test
    func firstLocalReadFindsTextFileInApprovedFolder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try Data("private local note".utf8).write(to: directory.appendingPathComponent("note.txt"))
        let folder = NdaniAllowedFolder(displayName: "Private", path: directory.path)

        let result = NdaniDesktopState.readFirstTextFilePreview(in: [folder])

        #expect(result.status == .ready)
        #expect(result.detail == "note.txt")
        #expect(result.preview == "private local note")
    }

    @Test
    func localReadLedgerStartsEmpty() {
        #expect(NdaniDesktopState().localReadLedger.isEmpty)
    }

    @Test
    func localReadLedgerRecordsMetadataWithoutPreviewContent() throws {
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("private local note".utf8).write(to: directory.appendingPathComponent("note.txt"))
        let folder = NdaniAllowedFolder(displayName: "Private", path: directory.path)
        let state = NdaniDesktopState(allowedFolders: [folder], permissionStoreDirectory: storeDir)
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

        state.readFirstTextFilePreview(now: timestamp)

        let entry = try #require(state.localReadLedger.first)
        #expect(entry.timestamp == timestamp)
        #expect(entry.folderPath == directory.path)
        #expect(entry.filePath?.hasSuffix("note.txt") == true)
        #expect(entry.status == .ready)
        #expect(entry.previewLength == "private local note".count)
        #expect(entry.wasSentOffDevice == false)

        // Privacy invariant: stored JSON must not contain preview text
        let stored = try Data(contentsOf: storeDir.appendingPathComponent("read-ledger.json"))
        let storedText = String(data: stored, encoding: .utf8) ?? ""
        #expect(storedText.contains("private local note") == false)
    }

    @Test
    func localReadLedgerRecordsNoFolderFailure() throws {
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let state = NdaniDesktopState(permissionStoreDirectory: storeDir)

        state.readFirstTextFilePreview()

        let entry = try #require(state.localReadLedger.first)
        #expect(entry.status == .noFolder)
        #expect(entry.folderPath == nil)
        #expect(entry.filePath == nil)
        #expect(entry.previewLength == 0)
        #expect(entry.wasSentOffDevice == false)
    }

    @Test
    func localReadLedgerRecordsStalePermissionFailure() throws {
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let folder = NdaniAllowedFolder(
            displayName: "Private",
            path: "/Users/example/Private",
            isBookmarkStale: true
        )
        let state = NdaniDesktopState(allowedFolders: [folder], permissionStoreDirectory: storeDir)

        state.readFirstTextFilePreview()

        let entry = try #require(state.localReadLedger.first)
        #expect(entry.status == .stalePermission)
        #expect(entry.folderPath == "/Users/example/Private")
        #expect(entry.filePath == nil)
        #expect(entry.previewLength == 0)
    }

    @Test
    func localReadLedgerRecordsMissingFileFailure() throws {
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = NdaniDesktopState(
            allowedFolders: [NdaniAllowedFolder(displayName: "Private", path: directory.path)],
            permissionStoreDirectory: storeDir
        )

        state.readFirstTextFilePreview()

        let entry = try #require(state.localReadLedger.first)
        #expect(entry.status == .missingFile)
        #expect(entry.folderPath == directory.path)
        #expect(entry.filePath == nil)
        #expect(entry.previewLength == 0)
    }

    @Test
    func localReadLedgerRecordsSymlinkEscapeWithoutPreviewContent() throws {
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let approved = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: approved, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: approved)
            try? FileManager.default.removeItem(at: outside)
        }

        let outsideFile = outside.appendingPathComponent("secret.md")
        try Data("outside secret".utf8).write(to: outsideFile)
        let linkURL = approved.appendingPathComponent("linked.md")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: outsideFile)
        let state = NdaniDesktopState(
            allowedFolders: [NdaniAllowedFolder(displayName: "Private", path: approved.path)],
            permissionStoreDirectory: storeDir
        )

        let result = NdaniDesktopState.readTextFilePreview(
            fileURL: linkURL,
            allowedFolder: try #require(state.allowedFolders.first)
        )
        state.appendLocalReadLedgerEntry(NdaniDesktopState.localReadLedgerEntry(from: result))

        let entry = try #require(state.localReadLedger.first)
        #expect(entry.status == .outsideApprovedFolder)
        #expect(entry.previewLength == 0)
        // Privacy invariant: stored JSON must not contain content from outside approved folder
        let stored = try Data(contentsOf: storeDir.appendingPathComponent("read-ledger.json"))
        let storedText = String(data: stored, encoding: .utf8) ?? ""
        #expect(storedText.contains("outside secret") == false)
    }

    @Test
    func localReadLedgerPersistsAndLoads() throws {
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let entry = NdaniLocalReadLedgerEntry(
            timestamp: Date(timeIntervalSince1970: 1_800_000_001),
            folderPath: "/Users/example/Private",
            filePath: "/Users/example/Private/note.md",
            status: .ready,
            previewLength: 42
        )

        NdaniDesktopState.saveLocalReadLedger([entry], storeDirectory: storeDir)
        let loaded = NdaniDesktopState.loadLocalReadLedger(storeDirectory: storeDir)

        #expect(loaded == [entry])
    }

    @Test
    func localReadLedgerKeepsNewestEntriesWithinLimit() throws {
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let state = NdaniDesktopState(permissionStoreDirectory: storeDir)

        for index in 0..<(NdaniDesktopState.maxLocalReadLedgerEntries + 3) {
            state.appendLocalReadLedgerEntry(
                NdaniLocalReadLedgerEntry(
                    timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                    folderPath: "/tmp",
                    filePath: "/tmp/\(index).md",
                    status: .ready,
                    previewLength: index
                )
            )
        }

        #expect(state.localReadLedger.count == NdaniDesktopState.maxLocalReadLedgerEntries)
        #expect(state.localReadLedger.first?.previewLength == NdaniDesktopState.maxLocalReadLedgerEntries + 2)
        #expect(state.localReadLedger.last?.previewLength == 3)
    }

    @Test
    func revokeAllFoldersDoesNotEraseLocalReadLedger() {
        let state = NdaniDesktopState(
            allowedFolders: [NdaniAllowedFolder(displayName: "Private", path: "/tmp")],
            localReadLedger: [
                NdaniLocalReadLedgerEntry(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_003),
                    folderPath: "/tmp",
                    filePath: "/tmp/note.md",
                    status: .ready,
                    previewLength: 4
                ),
            ]
        )

        state.revokeAllFolders()

        #expect(state.allowedFolders.isEmpty)
        #expect(state.localReadLedger.count == 1)
    }

    @Test
    func clearLocalReadLedgerRemovesSavedEntries() throws {
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let state = NdaniDesktopState(permissionStoreDirectory: storeDir)
        state.appendLocalReadLedgerEntry(
            NdaniLocalReadLedgerEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_002),
                folderPath: "/tmp",
                filePath: "/tmp/note.md",
                status: .ready,
                previewLength: 4
            )
        )

        state.clearLocalReadLedger()

        #expect(state.localReadLedger.isEmpty)
        #expect(NdaniDesktopState.loadLocalReadLedger(storeDirectory: storeDir).isEmpty)
    }

    @Test
    func folderGrantsAreExplicitAndRevocable() {
        let state = NdaniDesktopState()

        state.addAllowedFolder(displayName: "Private", path: "/Users/example/Private")
        state.addAllowedFolder(displayName: "Private", path: "/Users/example/Private")

        #expect(state.allowedFolderCount == 1)

        state.revokeAllFolders()

        #expect(state.allowedFolderCount == 0)
    }

}
