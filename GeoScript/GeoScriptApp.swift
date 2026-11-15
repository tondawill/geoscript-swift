import GeoEngine
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let geoscript = UTType(exportedAs: "tonda.geoscript", conformingTo: .plainText)
}

/// A .geoscript file. The text is kept so that saving writes exactly what the drawing last produced.
struct GeoDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.geoscript, .plainText]
    static let writableContentTypes: [UTType] = [.geoscript]

    var contents = FileContents(construction: Construction())
    var text = ""

    init() {}

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8),
              case .success(let contents) = importFile(text, TypingContext(center: Vec(x: 0, y: 0))) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.contents = contents
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // A new drawing that was never changed has no text yet.
        let output = text.isEmpty ? exportFile(contents, steps: [], stepsTitle: "Construction steps", exerciseTitle: "Exercise") : text
        return FileWrapper(regularFileWithContents: Data(output.utf8))
    }
}

extension FocusedValues {
    /// The drawing of the frontmost window, for the menu commands.
    @Entry var drawingStore: DrawingStore?
}

@main
struct GeoScriptApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: GeoDocument()) { file in
            ContentView(document: file.$document)
                .frame(minWidth: 900, minHeight: 540)
        }
        .defaultSize(width: 1280, height: 800)
        .commands { UndoCommands() }
    }
}

private struct UndoCommands: Commands {
    @FocusedValue(\.drawingStore) private var store

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { store?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(store == nil)
            Button("Redo") { store?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(store == nil)
        }
    }
}
