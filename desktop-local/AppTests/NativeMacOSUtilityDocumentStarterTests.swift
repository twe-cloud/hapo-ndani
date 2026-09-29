import Testing
import AppCore
import AppDocuments

@MainActor
struct NativeMacOSUtilityDocumentStarterTests {
    @Test
    func defaultModelTierIsDesktop() {
        #expect(NdaniDesktopState().selectedTier == .desktop)
    }

    @Test
    func documentStartsWithLocalNoteText() {
        #expect(StarterDocument().text.contains("Hapo Ndani local note"))
    }
}
