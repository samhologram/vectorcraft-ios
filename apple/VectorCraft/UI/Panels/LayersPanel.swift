import SwiftUI
import VectorCraftKit

/// The layer tree: eye and lock toggles, tap to select, drag to reorder, swipe to delete, new layer.
struct LayersPanel: View {
    let model: DocumentModel

    @State private var renaming: LayerRow?
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.layers, id: \.id) { row in
                    LayerRowView(model: model, row: row, onRename: {
                        newName = row.name
                        renaming = row
                    })
                    .listRowInsets(EdgeInsets(top: 2, leading: 8 + CGFloat(row.depth) * 16, bottom: 2, trailing: 8))
                }
            }
            .listStyle(.plain)
            .overlay {
                if model.layers.isEmpty {
                    PanelEmpty(title: "No Layers", symbol: "square.stack.3d.up", message: "The document has no layers yet.")
                }
            }
            .accessibilityIdentifier("control.layers.list")
            Divider()
            HStack(spacing: 10) {
                CommandButton(model: model, id: "layer.new", title: "New Layer", symbol: "plus")
                    .buttonStyle(.glass)
                CommandButton(model: model, id: "layer.newSublayer", title: "Sublayer", symbol: "plus.square.on.square")
                    .buttonStyle(.glass)
                Spacer()
                let ids = model.layers.filter(\.selected).map(\.id)
                Button {
                    model.run("layer.duplicate", ["ids": ids])
                } label: { Image(systemName: "square.on.square") }
                .buttonStyle(.glass)
                .disabled(ids.isEmpty)
                .accessibilityLabel("Duplicate")
                .accessibilityIdentifier("control.layers.duplicate")
                Button(role: .destructive) {
                    model.run("layer.delete", ["ids": ids])
                } label: { Image(systemName: "trash") }
                .buttonStyle(.glass)
                .disabled(ids.isEmpty)
                .accessibilityLabel("Delete")
                .accessibilityIdentifier("control.layers.delete")
            }
            .padding(10)
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
                .accessibilityIdentifier("control.layers.renameField")
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let r = renaming { model.run("layer.setProps", ["id": r.id, "name": newName]) }
                renaming = nil
            }
            .accessibilityIdentifier("control.layers.renameOK")
        }
        .accessibilityIdentifier("control.layers")
    }
}

private struct LayerRowView: View {
    let model: DocumentModel
    let row: LayerRow
    let onRename: () -> Void

    private var isLayer: Bool { row.kind == "Layer" }

    private var symbol: String {
        switch row.kind {
        case "Layer": return "square.stack.3d.up"
        case "Group": return "rectangle.3.group"
        case "Type": return "textformat"
        case "Image": return "photo"
        case "Symbol": return "star"
        case "Compound Path": return "square.on.square.dashed"
        default: return "scribble.variable"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.run("layer.setProps", ["id": row.id, "visible": !row.visible])
            } label: {
                Image(systemName: row.visible ? "eye" : "eye.slash")
                    .frame(width: 28, height: 28)
                    .foregroundStyle(row.visible ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.visible ? "Hide" : "Show")
            .accessibilityIdentifier("layer.\(row.id).visible")
            Button {
                model.run("layer.setProps", ["id": row.id, "locked": !row.locked])
            } label: {
                Image(systemName: row.locked ? "lock.fill" : "lock.open")
                    .frame(width: 28, height: 28)
                    .foregroundStyle(row.locked ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.locked ? "Unlock" : "Lock")
            .accessibilityIdentifier("layer.\(row.id).locked")
            Button {
                select()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 22)
                    Text(verbatim: row.name.isEmpty ? row.kind : row.name)
                        .lineLimit(1)
                        .foregroundStyle(row.visible ? Color.primary : Color.secondary)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("layer.\(row.id)")
        }
        .padding(.vertical, 2)
        .listRowBackground(row.selected ? Color.accentColor.opacity(0.18) : Color.clear)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                model.run("layer.delete", ["ids": [row.id]])
            } label: { Label("Delete", systemImage: "trash") }
        }
        .contextMenu {
            Button("Rename…", action: onRename)
            Button {
                model.run("layer.duplicate", ["ids": [row.id]])
            } label: { Label("Duplicate", systemImage: "square.on.square") }
            Button(role: .destructive) {
                model.run("layer.delete", ["ids": [row.id]])
            } label: { Label("Delete", systemImage: "trash") }
        }
        .draggable(String(row.id))
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first, let dragged = UInt64(first), dragged != row.id else { return false }
            let draggedIsLayer = model.layers.first { $0.id == dragged }?.kind == "Layer"
            let place = (isLayer && !draggedIsLayer) ? "inside" : "above"
            model.run("layer.move", ["ids": [dragged], "target": row.id, "place": place])
            return true
        }
    }

    private func select() {
        if isLayer {
            model.run("layer.target", ["id": row.id])
        } else {
            model.run("select.set", ["ids": [row.id]])
        }
    }
}
