import Foundation

/// Where the optional Hapo Ndani account backend lives.
///
/// Everything that makes Hapo Ndani useful — chat, journal, memory, local model
/// loading — runs entirely on your machine and never touches this. The backend
/// only serves the hosted extras: licence checks, the data marketplace, and the
/// update manifest. That service is not part of this repository, so this value
/// is empty by default and those features stay switched off until you point it
/// somewhere.
///
/// Set it in one of two ways, checked in this order:
///
/// 1. the `NDANI_BACKEND_BASE_URL` environment variable, or
/// 2. an `NdaniBackendBaseURL` string in the app target's Info.plist.
///
/// Use an origin with no trailing slash, e.g. `https://api.example.com`.
public enum NdaniBackendConfig {

    /// Base origin of the account backend, or `""` when none is configured.
    public static let baseURL: String = {
        if let fromEnvironment = ProcessInfo.processInfo.environment["NDANI_BACKEND_BASE_URL"],
           !fromEnvironment.isEmpty {
            return normalized(fromEnvironment)
        }
        if let fromInfoPlist = Bundle.main.object(forInfoDictionaryKey: "NdaniBackendBaseURL") as? String,
           !fromInfoPlist.isEmpty {
            return normalized(fromInfoPlist)
        }
        return ""
    }()

    /// `true` when a backend origin has been supplied.
    public static var isConfigured: Bool { !baseURL.isEmpty }

    /// Build a backend URL, or `nil` when no backend is configured.
    ///
    /// Callers treat `nil` as "this hosted feature is unavailable" rather than
    /// as an error, which is what a local-only build should do.
    public static func url(_ path: String) -> URL? {
        guard isConfigured else { return nil }
        return URL(string: baseURL + path)
    }

    /// Message to show a user who reached a hosted feature on a local-only build.
    public static let notConfiguredMessage =
        "This build has no account backend configured, so hosted features are turned off. "
        + "Local chat, journal, and memory are unaffected."

    private static func normalized(_ origin: String) -> String {
        var value = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }
}
