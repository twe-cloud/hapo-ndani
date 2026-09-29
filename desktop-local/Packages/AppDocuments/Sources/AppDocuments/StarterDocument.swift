import SwiftUI
import UniformTypeIdentifiers

public struct StarterDocument: FileDocument {
    public static let readableContentTypes: [UTType] = [.plainText]

    public var text: String

    public init(text: String = "Hapo Ndani local note\n\nDrop private notes here only after the user chooses a local file workflow.") {
        self.text = text
    }

    public init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            text = ""
        }
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

public struct StarterDocumentView: View {
    @Binding private var document: StarterDocument

    public init(document: Binding<StarterDocument>) {
        _document = document
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Local document")
                .font(.headline)
            Text("This file stays local unless the user explicitly exports or shares it.")
                .foregroundStyle(.secondary)
            TextEditor(text: $document.text)
                .font(.body.monospaced())
        }
        .padding()
    }
}
