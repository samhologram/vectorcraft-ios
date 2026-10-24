import SwiftUI
import UniformTypeIdentifiers
import UIKit
@preconcurrency import VectorCraftKit

/// A VectorCraft document (CONTRACT §2). New documents are empty 1080 x 1080 artboards; `.vectorcraft`, legacy
/// `.drawcraft`, SVG, PDF, AI and EPS files open through the engine importers and are saved back as `.vectorcraft`.
final class VectorCraftDocument: ReferenceFileDocument, @unchecked Sendable {
    typealias Snapshot = Data

    static var readableContentTypes: [UTType] {
        [.vectorcraftDocument, .drawcraftLegacy, .svg, .pdf, .illustratorArtwork, .encapsulatedPostScript,
         .png, .jpeg, .heic, .tiff, .gif, .webP, .image]
    }
    static var writableContentTypes: [UTType] { [.vectorcraftDocument] }

    /// The engine document, for `snapshot` (thread-safe, so no hop to the main actor is needed).
    private let handle: DocumentHandle
    /// Whether this document was made by File > New (the demo seeds it).
    private let isNew: Bool
    /// An engine error met while making the document, shown once the model exists.
    private let initError: String?
    /// Empty for native/new documents. Foreign content always saves to an app-owned native copy.
    private let originalData: Data
    private let originalKey: String
    private let originalBaseName: String
    private let preserveOriginal: Bool
    private let copyWriteLock = NSLock()
    private let copyQueue = DispatchQueue(label: "ca.hologram.vectorcraft.nativecopy", qos: .utility)
    private let copyScheduleLock = NSLock()
    private var copyGeneration = 0
    private var copyURL: URL?
    /// Made on first use on the main actor: `DocumentGroup` creates and reads documents on background
    /// threads (a new document is written, then read back through `init(configuration:)`), where the
    /// main-actor model must not be built.
    @MainActor private var madeModel: DocumentModel?

    /// The editor state (main-actor), built on first access from the scene's view.
    @MainActor var model: DocumentModel {
        if let madeModel { return madeModel }
        let m = DocumentModel(handle: handle)
        if !originalKey.isEmpty { m.onDirty = { [weak self] in self?.scheduleCopyWrite() } }
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
        originalData = Data()
        originalKey = ""
        originalBaseName = ""
        preserveOriginal = false
    }

    private init(handle: DocumentHandle, key: String, baseName: String, copy: URL?) {
        self.handle = handle
        isNew = false
        initError = nil
        originalData = Data()
        originalKey = key
        originalBaseName = baseName
        preserveOriginal = false
        copyURL = copy
    }

    /// New from Photo returns a document with the selected image as artwork, never an empty artboard.
    static func fromPhoto(_ data: Data) throws -> VectorCraftDocument {
        let key = VectorNativeCopyMap.key(name: "Photo", data: data)
        let copy = VectorNativeCopyMap.existingCopy(for: key)
        let reopened = copy.flatMap { try? DocumentHandle.open(path: $0.path) }
        let handle = try reopened ?? openImage(data: data, name: "Photo.heic")
        let document = VectorCraftDocument(handle: handle, key: key, baseName: "Photo", copy: reopened == nil ? nil : copy)
        let preparedSnapshot = try handle.saveNative()
        try document.writeNativeCopy()
        if let copy = VectorNativeCopyMap.existingCopy(for: key) {
            VectorNativeCopyMap.remember(copy, for: VectorNativeCopyMap.preparedPhotoKey(data: preparedSnapshot))
        }
        return document
    }

    required convenience init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(sourceData: data, fileName: configuration.file.filename ?? configuration.file.preferredFilename ?? "Untitled", contentType: configuration.contentType)
    }

    /// The same byte-level path DocumentGroup uses when it reopens a prepared native document.
    init(sourceData data: Data, fileName: String, contentType: UTType) throws {
        AppEnvironment.bootstrap()
        // The engine reads from a path and picks the importer from the extension and the content.
        var name = fileName
        if (name as NSString).pathExtension.isEmpty,
           let ext = contentType.preferredFilenameExtension {
            name += "." + ext
        }
        name = (name as NSString).lastPathComponent
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Open", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let native = contentType.conforms(to: .vectorcraftDocument)
            || (name as NSString).pathExtension.lowercased() == "vectorcraft"
        let preparedKey = native ? VectorNativeCopyMap.preparedPhotoKey(data: data) : ""
        let key = native
            ? (VectorNativeCopyMap.existingCopy(for: preparedKey) == nil ? "" : preparedKey)
            : VectorNativeCopyMap.key(name: name, data: data)
        let copy = key.isEmpty ? nil : VectorNativeCopyMap.existingCopy(for: key)
        let reopened = copy.flatMap { try? DocumentHandle.open(path: $0.path) }
        handle = try reopened ?? Self.openImageOrDocument(data: data, name: name, directory: dir)
        isNew = false
        initError = nil
        originalData = key.isEmpty ? Data() : data
        originalKey = key
        originalBaseName = native && !key.isEmpty ? "Photo" : (name as NSString).deletingPathExtension
        preserveOriginal = !native || !key.isEmpty
        copyURL = reopened == nil ? nil : copy
    }

    func snapshot(contentType: UTType) throws -> Data {
        try handle.saveNative()
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        guard !originalKey.isEmpty else { return FileWrapper(regularFileWithContents: snapshot) }
        let latest = try writeNativeCopy()
        return preserveOriginal
            ? (configuration.existingFile ?? FileWrapper(regularFileWithContents: originalData))
            : FileWrapper(regularFileWithContents: latest)
    }

    /// Called after an edit, independent of DocumentGroup's autosave timing.
    private func scheduleCopyWrite() {
        copyScheduleLock.lock()
        copyGeneration += 1
        let generation = copyGeneration
        copyScheduleLock.unlock()
        // Keep the document alive until its last edit is copied, even if Back closes the scene meanwhile.
        copyQueue.asyncAfter(deadline: .now() + 1) { [self] in
            self.copyScheduleLock.lock()
            let current = self.copyGeneration == generation
            self.copyScheduleLock.unlock()
            if current { _ = try? self.writeNativeCopy() }
        }
    }

    @discardableResult private func writeNativeCopy() throws -> Data {
        copyWriteLock.lock(); defer { copyWriteLock.unlock() }
        let url = try copyDestination()
        // Export the latest state under the serial lock; an older SwiftUI snapshot cannot replace a newer copy.
        let latest = try handle.saveNative()
        var coordinatedError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatedError) { target in
            do { try latest.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinatedError ?? writeError { throw error }
        VectorNativeCopyMap.remember(url, for: originalKey)
        return latest
    }

    private func copyDestination() throws -> URL {
        if let copyURL { return copyURL }
        let folder = VectorCloudContainer.documentsFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = originalBaseName.isEmpty ? "Untitled" : originalBaseName
        var candidate = folder.appending(path: "\(base).vectorcraft")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(base) \(number).vectorcraft")
            number += 1
        }
        copyURL = candidate
        return candidate
    }

    private static func openImageOrDocument(data: Data, name: String, directory: URL) throws -> DocumentHandle {
        let ext = (name as NSString).pathExtension.lowercased()
        let supportedImages: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "tif", "tiff", "bmp"]
        let fileName: String
        let bytes: Data
        if !supportedImages.contains(ext), UTType(filenameExtension: ext)?.conforms(to: .image) == true {
            guard let png = UIImage(data: data)?.pngData() else { throw CocoaError(.fileReadCorruptFile) }
            fileName = "Image.png"
            bytes = png
        } else {
            fileName = name
            bytes = data
        }
        let url = directory.appendingPathComponent(fileName)
        try bytes.write(to: url, options: .atomic)
        return try DocumentHandle.open(path: url.path)
    }

    private static func openImage(data: Data, name: String) throws -> DocumentHandle {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("VectorPhoto-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try openImageOrDocument(data: data, name: name, directory: dir)
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
