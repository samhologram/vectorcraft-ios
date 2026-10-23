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

    /// The engine document, for `snapshot` (thread-safe, so no hop to the main actor is needed).
    private let handle: DocumentHandle
    /// Whether this document was made by File > New (the demo seeds it).
    private let isNew: Bool
    /// An engine error met while making the document, shown once the model exists.
    private let initError: String?
    /// Made on first use on the main actor: `DocumentGroup` creates and reads documents on background
    /// threads (a new document is written, then read back through `init(configuration:)`), where the
    /// main-actor model must not be built.
    @MainActor private var madeModel: DocumentModel?

    /// The editor state (main-actor), built on first access from the scene's view.
    @MainActor var model: DocumentModel {
        if let madeModel { return madeModel }
        let m = DocumentModel(handle: handle)
        m.lastError = initError
        // A new document, or the empty file DocumentGroup reads back after creating one, gets the demo art.
        m.isNewDocument = isNew || m.isEmptyDocument
        if AppSettings.isDemo && m.isNewDocument { m.seedDemo() }
        madeModel = m
        return m
    }

    /// File > New.
    init() {
        AppEnvironment.bootstrap()
        var error: String?
        var made = try? DocumentHandle.newDocument(width: 1080, height: 1080, preset: "")
        if made == nil {
            error = "VectorCraft could not create a document."
            made = Self.fallbackHandle()
        }
        // `fallbackHandle` only fails when the engine library itself is broken.
        handle = made ?? Self.lastResortHandle()
        isNew = true
        initError = error
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
        handle = try DocumentHandle.open(path: url.path)
        isNew = false
        initError = nil
    }

    func snapshot(contentType: UTType) throws -> Data {
        try handle.saveNative()
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}

extension VectorCraftDocument {
    /// Another document size, then a blank SVG import, for the (practically impossible) case that File > New fails.
    static func fallbackHandle() -> DocumentHandle? {
        if let h = try? DocumentHandle.newDocument(width: 595, height: 842, preset: "") { return h }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("blank-\(UUID().uuidString).svg")
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"800\" height=\"600\"></svg>"
        guard (try? svg.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return try? DocumentHandle.open(path: url.path)
    }

    /// Keeps trying: `DocumentGroup` needs a document, and every engine call is panic-safe, so this only spins
    /// if the engine library cannot make any document at all.
    static func lastResortHandle() -> DocumentHandle {
        while true {
            if let h = fallbackHandle() { return h }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}

extension DocumentModel {
    /// No art yet: only layers in the layer list.
    var isEmptyDocument: Bool { layers.allSatisfy { $0.depth == 0 } }
}
