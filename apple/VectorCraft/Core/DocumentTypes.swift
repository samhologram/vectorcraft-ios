import UniformTypeIdentifiers

/// Document types (CONTRACT §2). The exported type is declared in Info.plist (project.yml); the imported ones are
/// readable through the engine importers and saved back as `.vectorcraft`.
extension UTType {
    /// `.vectorcraft`: the only writable type.
    static let vectorcraftDocument = UTType(exportedAs: "ca.hologram.vectorcraft.document", conformingTo: .data)
    /// Legacy `.drawcraft` (the app was called DrawCraft).
    static let drawcraftLegacy = UTType(importedAs: "ca.hologram.vectorcraft.legacy", conformingTo: .data)
    static let illustratorArtwork = UTType(importedAs: "com.adobe.illustrator.ai-image")
    static let encapsulatedPostScript = UTType(importedAs: "com.adobe.encapsulated-postscript")
}
