import Foundation

public enum NdaniPlatformKind: String, CaseIterable, Sendable {
    case mac
    case iPad
    case iPhone

    public var title: String {
        switch self {
        case .mac: "Mac"
        case .iPad: "iPad"
        case .iPhone: "iPhone"
        }
    }
}

public enum NdaniCapabilityMode: String, CaseIterable, Sendable {
    case desktopStrong
    case tabletBalanced
    case phoneConversational
    case phoneSafe
    case captureOnly

    public var title: String {
        switch self {
        case .desktopStrong: "Desktop Strong"
        case .tabletBalanced: "Tablet Balanced"
        case .phoneConversational: "Phone Conversational"
        case .phoneSafe: "Phone Safe"
        case .captureOnly: "Capture Only"
        }
    }

    public var recommendedTier: NdaniModelTier? {
        switch self {
        case .desktopStrong: .desktop
        case .tabletBalanced: .phone
        case .phoneConversational: .desktop
        case .phoneSafe: nil
        case .captureOnly: nil
        }
    }

    public var userPromise: String {
        switch self {
        case .desktopStrong:
            "Full private AI journal, chat, local memory, approved folders, and stronger local models."
        case .tabletBalanced:
            "Journal-first private chat with local memory, document picker access, and smaller model packages."
        case .phoneConversational:
            "Human-level private chat only on high-memory iPhones that can run an 8B-class local model."
        case .phoneSafe:
            "Pocket journal and quick memory capture. Full private chat continues on iPad or Mac until a stronger phone model passes."
        case .captureOnly:
            "Private capture and local memory first. Continue heavier AI work on iPad or Mac."
        }
    }
}

public struct NdaniPlatformCapability: Equatable, Sendable {
    public let platform: NdaniPlatformKind
    public let mode: NdaniCapabilityMode
    public let physicalMemoryBytes: UInt64
    public let recommendedDownloadTitle: String
    public let limitations: [String]

    public init(
        platform: NdaniPlatformKind,
        mode: NdaniCapabilityMode,
        physicalMemoryBytes: UInt64,
        recommendedDownloadTitle: String,
        limitations: [String]
    ) {
        self.platform = platform
        self.mode = mode
        self.physicalMemoryBytes = physicalMemoryBytes
        self.recommendedDownloadTitle = recommendedDownloadTitle
        self.limitations = limitations
    }

    public static func current(userInterfaceIdiom: String? = nil, physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> NdaniPlatformCapability {
        #if os(macOS)
        return .mac(physicalMemory: physicalMemory)
        #elseif os(iOS)
        if userInterfaceIdiom == "pad" {
            return .iPad(physicalMemory: physicalMemory)
        }
        return .iPhone(physicalMemory: physicalMemory)
        #else
        return NdaniPlatformCapability(platform: .iPhone, mode: .captureOnly, physicalMemoryBytes: physicalMemory, recommendedDownloadTitle: "No model download recommended", limitations: ["This platform has not been qualified yet."])
        #endif
    }

    public static func mac(physicalMemory: UInt64) -> NdaniPlatformCapability {
        let gib = physicalMemory / 1_073_741_824
        return NdaniPlatformCapability(
            platform: .mac,
            mode: .desktopStrong,
            physicalMemoryBytes: physicalMemory,
            recommendedDownloadTitle: gib >= 16 ? "Large desktop model package" : "Standard desktop fallback package",
            limitations: gib >= 16 ? [] : ["Use the 8B Standard fallback on low-memory laptops."]
        )
    }

    public static func iPad(physicalMemory: UInt64) -> NdaniPlatformCapability {
        let gib = physicalMemory / 1_073_741_824
        let mode: NdaniCapabilityMode = gib >= 6 ? .tabletBalanced : .captureOnly
        return NdaniPlatformCapability(
            platform: .iPad,
            mode: mode,
            physicalMemoryBytes: physicalMemory,
            recommendedDownloadTitle: mode == .tabletBalanced ? "Lite tablet model package" : "No model download recommended yet",
            limitations: mode == .tabletBalanced
                ? ["Use 4B Lite only for narrow tablet prompts until a stronger iPad model passes.", "Folder access is document-picker scoped."]
                : ["This iPad is best for journal and memory capture until model hardware checks pass."]
        )
    }

    public static func iPhone(physicalMemory: UInt64) -> NdaniPlatformCapability {
        let gib = physicalMemory / 1_073_741_824
        let mode: NdaniCapabilityMode
        if gib >= 8 {
            mode = .phoneConversational
        } else if gib >= 6 {
            mode = .phoneSafe
        } else {
            mode = .captureOnly
        }
        return NdaniPlatformCapability(
            platform: .iPhone,
            mode: mode,
            physicalMemoryBytes: physicalMemory,
            recommendedDownloadTitle: mode == .phoneConversational ? "Baseline iPhone model package" : "No model download recommended yet",
            limitations: {
                switch mode {
                case .phoneConversational:
                    return ["Use an 8B-class local model as the iPhone conversation floor.", "Large folder workflows still belong on iPad or Mac."]
                case .phoneSafe:
                    return ["Do not use 4B Lite as the human conversation baseline.", "Capture entries locally here, then use iPad or Mac for heavier AI work."]
                default:
                    return ["Capture entries locally here, then use iPad or Mac for heavier AI work."]
                }
            }()
        )
    }
}
