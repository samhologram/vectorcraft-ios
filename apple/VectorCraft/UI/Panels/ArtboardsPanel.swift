import SwiftUI
import VectorCraftKit

/// Artboards: list (`artboard.<index>`), go to, rename, duplicate, delete, add, fit to artwork.
struct ArtboardsPanel: View {
    let model: DocumentModel

    @State private var renaming: ArtboardInfo?
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.state.artboards, id: \.index) { a in
                    let active = a.index == model.state.activeArtboard
                    Button {
                        model.runUI("view.goToArtboard", ["index": Int(a.index)])
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.dashed")
                                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: a.name).lineLimit(1)
                                Text(verbatim: String(format: "%.0f × %.0f pt", a.rect.width, a.rect.height))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if active { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(active ? Color.accentColor.opacity(0.15) : Color.clear)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("artboard.\(a.index)")
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.run("artboard.delete", ["index": Int(a.index)])
                        } label: { Label("Delete", systemImage: "trash") }
                        .disabled(model.state.artboards.count < 2)
                    }
                    .contextMenu {
                        Button("Rename…") { newName = a.name; renaming = a }
                        Button {
                            model.run("artboard.duplicate", ["index": Int(a.index)])
                        } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        Button {
                            model.run("artboard.fitToArt", ["index": Int(a.index)])
                        } label: { Label("Fit to Artwork", systemImage: "arrow.up.left.and.arrow.down.right") }
                    }
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("control.artboards.list")
            Divider()
            HStack(spacing: 10) {
                CommandButton(model: model, id: "artboard.new", title: "New Artboard", symbol: "plus")
                    .buttonStyle(.glass)
                CommandButton(model: model, id: "artboard.rearrange", title: "Rearrange", symbol: "square.grid.2x2")
                    .buttonStyle(.glass)
                Spacer()
                Button(role: .destructive) {
                    model.run("artboard.delete", ["index": Int(model.state.activeArtboard)])
                } label: { Image(systemName: "trash") }
                .buttonStyle(.glass)
                .disabled(model.state.artboards.count < 2)
                .accessibilityLabel("Delete Artboard")
                .accessibilityIdentifier("control.artboards.delete")
            }
            .padding(10)
        }
        .alert("Rename Artboard", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
                .accessibilityIdentifier("control.artboards.renameField")
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let a = renaming { model.run("artboard.setProps", ["index": Int(a.index), "name": newName]) }
                renaming = nil
            }
        }
        .accessibilityIdentifier("control.artboards")
    }
}
