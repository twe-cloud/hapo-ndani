import AppCore

public enum StarterFixtures {
    @MainActor
    public static func makeState() -> NdaniDesktopState {
        NdaniDesktopState()
    }
}
