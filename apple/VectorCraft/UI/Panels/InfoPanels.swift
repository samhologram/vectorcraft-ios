import SwiftUI
import VectorCraftKit

/// Document Info: the engine's text report (document, objects, fonts, images, swatches…).
struct DocInfoPanel: View {
    let model: DocumentModel
    @State private var text = ""
    @State private var selectionOnly = false

    var body: some View {
        Form {
            Section {
                row("Name", model.state.title)
                row("Color Mode", model.state.colorMode.uppercased())
                row("Artboards", "\(model.state.artboards.count)")
            }
            Section {
                Toggle("Selection Only", isOn: $selectionOnly)
                    .accessibilityIdentifier("control.docInfo.selectionOnly")
            }
            Section("Report") {
                Text(verbatim: text.isEmpty ? "Loading…" : text)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("control.docInfo.report")
            }
        }
        .task(id: "\(model.state.historyId)-\(selectionOnly)") { load() }
        .accessibilityIdentifier("control.docInfo")
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            Text(verbatim: value).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func load() {
        var p: [String: Any] = ["format": "text"]
        if selectionOnly { p["selectionOnly"] = true }
        if let out = model.quietQuery("document.info", p) as? [String: Any], let t = out["text"] as? String { text = t } else { text = "" }
    }
}

/// Info: the selection's size and position, paint and kinds, and the document.
struct InfoPanel: View {
    let model: DocumentModel

    var body: some View {
        Form {
            Section("Selection") {
                if model.selection.count == 0 {
                    Text("Nothing selected").foregroundStyle(.secondary)
                        .accessibilityIdentifier("control.info.none")
                } else {
                    row("Objects", "\(model.selection.count)", id: "count")
                    if !model.selection.kinds.isEmpty { row("Kind", model.selection.kinds.joined(separator: ", "), id: "kinds") }
                    if let b = model.selection.bounds {
                        row("X", fmt(b.x) + " pt", id: "x")
                        row("Y", fmt(b.y) + " pt", id: "y")
                        row("Width", fmt(b.width) + " pt", id: "width")
                        row("Height", fmt(b.height) + " pt", id: "height")
                    }
                    HStack {
                        Text("Fill"); Spacer(); PaintChip(paint: model.selection.fill, size: 22)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("control.info.fill")
                    HStack {
                        Text("Stroke"); Spacer()
                        if let w = model.selection.strokeWidth { Text(verbatim: fmt(w) + " pt").foregroundStyle(.secondary) }
                        PaintChip(paint: model.selection.stroke, size: 22, ring: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("control.info.stroke")
                    if let o = model.selection.opacity { row("Opacity", fmt(o * 100) + " %", id: "opacity") }
                }
            }
            Section("Document") {
                row("Zoom", String(format: "%.0f %%", model.view.zoom * 100), id: "zoom")
                row("Color Mode", model.state.colorMode.uppercased(), id: "colorMode")
                row("Tool", model.state.tool, id: "tool")
            }
        }
        .accessibilityIdentifier("control.info")
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    private func row(_ title: String, _ value: String, id: String) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            Text(verbatim: value).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("control.info.\(id)")
    }
}

/// Navigator: an artboard thumbnail and the view controls.
struct NavigatorPanel: View {
    let model: DocumentModel

    @State private var image: CGImage?
    @State private var index = 0

    var body: some View {
        Form {
            Section {
                if model.state.artboards.count > 1 {
                    Picker("Artboard", selection: $index) {
                        ForEach(model.state.artboards, id: \.index) { a in Text(verbatim: a.name).tag(Int(a.index)) }
                    }
                    .accessibilityIdentifier("control.navigator.artboard")
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    } else {
                        ProgressView()
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Artboard preview")
                .accessibilityIdentifier("control.navigator.thumbnail")
            }
            Section("View") {
                HStack {
                    Text("Zoom")
                    Spacer()
                    Text(verbatim: String(format: "%.0f %%", model.view.zoom * 100)).monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityIdentifier("control.navigator.zoom")
                }
                HStack(spacing: 8) {
                    Button { model.runUI("view.zoomOut") } label: { Image(systemName: "minus.magnifyingglass") }
                        .accessibilityLabel("Zoom Out")
                        .accessibilityIdentifier("control.navigator.zoomOut")
                    Button { model.runUI("view.zoomIn") } label: { Image(systemName: "plus.magnifyingglass") }
                        .accessibilityLabel("Zoom In")
                        .accessibilityIdentifier("control.navigator.zoomIn")
                    Button { model.fitArtboard() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .accessibilityLabel("Fit Artboard")
                        .accessibilityIdentifier("control.navigator.fit")
                    Button { model.runUI("view.actualSize") } label: { Text("100%").lineLimit(1) }
                        .accessibilityIdentifier("control.navigator.actualSize")
                }
                .buttonStyle(.glass)
            }
        }
        .task(id: "\(model.state.historyId)-\(index)") {
            image = await model.artboardThumbnail(index, edge: 480)
        }
        .onChange(of: index) { _, new in
            if new != Int(model.state.activeArtboard) { model.runUI("view.goToArtboard", ["index": new]) }
        }
        .onAppear { index = Int(model.state.activeArtboard) }
        .accessibilityIdentifier("control.navigator")
    }
}
