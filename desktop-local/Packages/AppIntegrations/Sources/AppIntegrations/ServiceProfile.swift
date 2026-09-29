public enum ServiceProfile: String, CaseIterable, Sendable {
    case localDesktop
    case phoneCompanion
    case explicitExternal

    public var title: String {
        switch self {
        case .localDesktop:
            "Local desktop"
        case .phoneCompanion:
            "Phone companion"
        case .explicitExternal:
            "Explicit external"
        }
    }

    public var description: String {
        switch self {
        case .localDesktop:
            "Runs private work on this Mac."
        case .phoneCompanion:
            "Keeps portable memory and permission prompts close."
        case .explicitExternal:
            "Requires separate consent before anything leaves the machine."
        }
    }
}
