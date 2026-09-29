import Testing
@testable import AppCore

@MainActor
struct NdaniPlatformTests {
    @Test
    func iPadWithEnoughMemoryUsesTabletBalancedMode() {
        let capability = NdaniPlatformCapability.iPad(physicalMemory: 8 * 1_073_741_824)
        #expect(capability.platform == .iPad)
        #expect(capability.mode == .tabletBalanced)
        #expect(capability.mode.recommendedTier == .phone)
        #expect(capability.recommendedDownloadTitle.contains("Lite"))
    }

    @Test
    func iPhoneWithLimitedMemoryFallsBackToCaptureOnly() {
        let capability = NdaniPlatformCapability.iPhone(physicalMemory: 4 * 1_073_741_824)
        #expect(capability.platform == .iPhone)
        #expect(capability.mode == .captureOnly)
        #expect(capability.mode.recommendedTier == nil)
    }

    @Test
    func iPhoneWithSixGBDoesNotOfferConversationalBaseline() {
        let capability = NdaniPlatformCapability.iPhone(physicalMemory: 6 * 1_073_741_824)

        #expect(capability.platform == .iPhone)
        #expect(capability.mode == .phoneSafe)
        #expect(capability.mode.recommendedTier == nil)
        #expect(NdaniDesktopState().recommendedPackage(for: capability) == nil)
        #expect(capability.limitations.contains { $0.localizedCaseInsensitiveContains("Do not use 4B Lite") })
    }

    @Test
    func iPhoneWithEightGBUsesEightBConversationFloor() throws {
        let capability = NdaniPlatformCapability.iPhone(physicalMemory: 8 * 1_073_741_824)
        let package = try #require(NdaniDesktopState().recommendedPackage(for: capability))

        #expect(capability.platform == .iPhone)
        #expect(capability.mode == .phoneConversational)
        #expect(capability.mode.recommendedTier == .desktop)
        #expect(package.id == "qwen3-8b-gguf")
    }

    @Test
    func macWithLargeMemoryUsesDesktopLargeMode() throws {
        let capability = NdaniPlatformCapability.mac(physicalMemory: 16 * 1_073_741_824)
        let package = try #require(NdaniDesktopState().recommendedPackage(for: capability))

        #expect(capability.platform == .mac)
        #expect(capability.mode == .desktopStrong)
        #expect(capability.mode.recommendedTier == .desktop)
        #expect(capability.recommendedDownloadTitle.contains("Large"))
        #expect(package.id == "qwen3-14b-gguf")
    }

    @Test
    func macWithLowMemoryUsesStandardFallbackPackage() throws {
        let capability = NdaniPlatformCapability.mac(physicalMemory: 8 * 1_073_741_824)
        let package = try #require(NdaniDesktopState().recommendedPackage(for: capability))

        #expect(capability.platform == .mac)
        #expect(capability.mode == .desktopStrong)
        #expect(capability.mode.recommendedTier == .desktop)
        #expect(capability.recommendedDownloadTitle.contains("Standard"))
        #expect(package.id == "qwen3-8b-gguf")
    }
}
