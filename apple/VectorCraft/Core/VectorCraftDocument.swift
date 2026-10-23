import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import VectorCraftKit

/// A VectorCraft document (CONTRACT §2). New documents are empty 1080 x 1080 artboards; `.vectorcraft`, legacy
/// `.drawcraft`, SVG, PDF, AI and EPS files open through the engine importers and are saved back as `.vectorcraft`.
final class VectorCraftDocument: ReferenceFileDocument {
    typealias Snapshot = Data

    static var readableContentTypes: [UTType] {
        [.vectorcraftDocument, .drawcraftLegacy, .svg, .pdf, .illustratorArtwork, .encapsulatedPostScript]
    }
    static var writableContentTypes: [UTType] { [.vectorcraftDocument] }

    /// The editor state (main-actor); the document system creates and saves documents on the main thread.
    let model: DocumentModel
    /// The engine document, for `snapshot` (thread-safe, so no hop to the main actor is needed).
    private let handle: DocumentHandle

    /// File > New.
    init() {
        AppEnvironment.bootstrap()
        let made: DocumentModel
        do {
            let handle = try DocumentHandle.newDocument(width: 1080, height: 1080, preset: "")
            made = MainActor.assumeIsolated { DocumentModel(handle: handle) }
        } catch {
            // The engine could not make a document: the error is shown by the placeholder model.
            let message = error.localizedDescription
            made = MainActor.assumeIsolated { DocumentModel.failed(message) }
        }
        model = made
        handle = made.handle
        MainActor.assumeIsolated {
            made.isNewDocument = true
            if AppSettings.isDemo { made.seedDemo() }
        }
    }

    required init(configuration: ReadConfiguration) throws {
        AppEnvironment.bootstrap()
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // The engine reads from a path and picks the importer from the extension and the content.
        var name = configuration.file.filename ?? configuration.file.preferredFilename ?? "Untitled"
        if (name as NSString).pathExtension.isEmpty,
           let ext = configuration.contentType.preferredFilenameExtension {
            name += "." + ext
        }
        name = (name as NSString).lastPathComponent
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Open", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        let opened = try DocumentHandle.open(path: url.path)
        model = MainActor.assumeIsolated { DocumentModel(handle: opened) }
        handle = opened
    }

    func snapshot(contentType: UTType) throws -> Data {
        try handle.saveNative()
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}

extension DocumentModel {
    /// A model for the (practically impossible) case that the engine could not create a document. Tries other
    /// sizes and a blank SVG import so the person sees the error in an alert instead of a crash.
    static func failed(_ message: String) -> DocumentModel {
        var handle = try? DocumentHandle.newDocument(width: 595, height: 842, preset: "")
        if handle == nil {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("blank-\(UUID().uuidString).svg")
            let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"800\" height=\"600\"></svg>"
            if (try? svg.write(to: url, atomically: true, encoding: .utf8)) != nil {
                handle = try? DocumentHandle.open(path: url.path)
            }
        }
        // `DocumentGroup` needs a non-optional document and the model a handle: with no engine document at all
        // there is nothing to show. Unreachable unless the engine library itself is broken.
        guard let handle else { preconditionFailure("VectorCraft engine could not create a document: \(message)") }
        let model = DocumentModel(handle: handle)
        model.lastError = message
        return model
    }
}
