import SwiftUI
import UniformTypeIdentifiers
import VectorCraftKit

/// Output bytes handed to `fileExporter`.
struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.svg, .pdf, .png] }
    let data: Data
    let type: UTType

    init(data: Data, type: UTType) {
        self.data = data
        self.type = type
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        type = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Export the active artboard as SVG, PDF or PNG through the engine, then share it or save it to Files.
struct ExportSheet: View {
    let model: DocumentModel

    @Environment(\.dismiss) private var dismiss
    @State private var format = "svg"
    @State private var artboard = 0
    @State private var scale = 2.0
    @State private var transparent = false
    @State private var working = false
    @State private var fileURL: URL?
    @State private var fileData: Data?
    @State private var errorText: String?
    @State private var saving = false

    private static let formats = ["svg", "pdf", "png"]

    private var type: UTType {
        switch format {
        case "pdf": return .pdf
        case "png": return .png
        default: return .svg
        }
    }

    private var baseName: String {
        let t = model.state.title.trimmingCharacters(in: .whitespaces)
        let stem = (t as NSString).deletingPathExtension
        return stem.isEmpty ? "Untitled" : stem
    }

    private func reset() {
        fileURL = nil
        fileData = nil
        errorText = nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $format) {
                        ForEach(Self.formats, id: \.self) { f in Text(verbatim: f.uppercased()).tag(f) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("export.format")
                    if model.state.artboards.count > 1 {
                        Picker("Artboard", selection: $artboard) {
                            ForEach(model.state.artboards, id: \.index) { a in
                                Text(verbatim: a.name).tag(Int(a.index))
                            }
                        }
                        .accessibilityIdentifier("export.artboard")
                    }
                    if format == "png" {
                        Picker("Scale", selection: $scale) {
                            Text("1×").tag(1.0)
                            Text("2×").tag(2.0)
                            Text("3×").tag(3.0)
                            Text("4×").tag(4.0)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("export.scale")
                        Toggle("Transparent background", isOn: $transparent)
                            .accessibilityIdentifier("export.transparent")
                    }
                } footer: {
                    Text("The artboard is exported with the engine’s own \(format.uppercased()) writer.")
                }
                if let errorText {
                    Section {
                        Text(verbatim: errorText).foregroundStyle(.red).textSelection(.enabled)
                            .accessibilityIdentifier("export.error")
                    }
                }
                Section {
                    if let fileURL {
                        ShareLink(item: fileURL) {
                            Label("Share \(format.uppercased())", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("export.share")
                        Button {
                            saving = true
                        } label: {
                            Label("Save to Files", systemImage: "folder")
                        }
                        .accessibilityIdentifier("export.saveToFiles")
                    } else {
                        Button {
                            Task { await export() }
                        } label: {
                            if working {
                                HStack { ProgressView(); Text("Exporting…") }
                            } else {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                        }
                        .disabled(working)
                        .accessibilityIdentifier("export.run")
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { model.showExport = false; dismiss() }
                        .accessibilityIdentifier("export.done")
                }
            }
            .fileExporter(
                isPresented: $saving,
                document: ExportFile(data: fileData ?? Data(), type: type),
                contentType: type,
                defaultFilename: baseName
            ) { result in
                if case .failure(let e) = result { errorText = e.localizedDescription }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: format) { _, _ in reset() }
        .onChange(of: artboard) { _, _ in reset() }
        .onChange(of: scale) { _, _ in reset() }
        .onChange(of: transparent) { _, _ in reset() }
        .onAppear { artboard = Int(model.state.activeArtboard) }
    }

    private func export() async {
        errorText = nil
        working = true
        defer { working = false }
        var options: [String: Any] = ["artboard": artboard]
        if format == "png" {
            options["scale"] = scale
            options["transparent"] = transparent
        }
        do {
            let data = try await model.exportData(format: format, options: options)
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("VectorCraftExport-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(baseName).appendingPathExtension(format)
            try data.write(to: url, options: .atomic)
            fileData = data
            fileURL = url
        } catch {
            errorText = error.localizedDescription
        }
    }
}
