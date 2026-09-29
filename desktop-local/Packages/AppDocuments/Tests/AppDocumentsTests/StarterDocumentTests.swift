import Testing
@testable import AppDocuments

struct StarterDocumentTests {
    @Test
    func defaultDocumentContainsLocalNoteText() {
        #expect(StarterDocument().text.contains("Hapo Ndani local note"))
    }
}
