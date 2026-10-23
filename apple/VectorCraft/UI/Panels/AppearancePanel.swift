import SwiftUI
import VectorCraftKit

/// Fills, strokes and effects of the selection: the stack, add fill / stroke / effect, remove, clear.
struct AppearancePanel: View {
    let model: DocumentModel

    struct Item: Identifiable {
        let index: Int
        let kind: String
        let effects: Int
        var id: Int { index }
    }
    struct EffectEntry: Identifiable {
        let id: String
        let label: String
        let menu: String
    }

    @State private var items: [Item] = []
    @State private var catalog: [EffectEntry] = []

    var body: some View {
        Form {
            Section("Contents") {
                NeedsSelectionNote(model: model)
                if model.selection.count > 0 {
                    HStack {
                        Label("Fill", systemImage: "square.fill")
                        Spacer()
                        PaintChip(paint: model.selection.fill, size: 24)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("control.appearance.fill")
                    HStack {
                        Label("Stroke", systemImage: "square")
                        Spacer()
                        Text(verbatim: String(format: "%.2f pt", model.selection.strokeWidth ?? 0))
                            .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        PaintChip(paint: model.selection.stroke, size: 24, ring: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("control.appearance.stroke")
                    OpacityControl(model: model, panelID: "appearance")
                }
            }
            if !items.isEmpty {
                Section("Stack") {
                    ForEach(items) { item in
                        HStack {
                            Image(systemName: item.kind == "fill" ? "square.fill" : "square")
                            Text(verbatim: item.kind.capitalized)
                            if item.effects > 0 {
                                Text(verbatim: "· \(item.effects) effect\(item.effects == 1 ? "" : "s")")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("control.appearance.item.\(item.index)")
                        .swipeActions {
                            Button(role: .destructive) {
                                model.run("appearance.removeItem", ["index": item.index])
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                }
            }
            Section("Add") {
                CommandButton(model: model, id: "appearance.addFill", title: "Add New Fill", symbol: "plus.square")
                CommandButton(model: model, id: "appearance.addStroke", title: "Add New Stroke", symbol: "plus.square")
                if !catalog.isEmpty {
                    Menu {
                        ForEach(groups, id: \.0) { title, entries in
                            Menu(title) {
                                ForEach(entries) { e in
                                    Button(e.label) { model.present("appearance.addEffect", params: ["effect": e.id]) }
                                        .accessibilityIdentifier("control.appearance.effect.\(e.id)")
                                }
                            }
                        }
                    } label: { Label("Add Effect", systemImage: "sparkles") }
                    .disabled(model.selection.count == 0)
                    .accessibilityIdentifier("control.appearance.addEffect")
                }
            }
            Section("Reset") {
                CommandButton(model: model, id: "appearance.reduceToBasic", title: "Reduce to Basic Appearance")
                CommandButton(model: model, id: "appearance.clear", title: "Clear Appearance", symbol: "xmark.circle")
            }
        }
        .task(id: model.selectionKey) { load() }
        .accessibilityIdentifier("control.appearance")
    }

    private var groups: [(String, [EffectEntry])] {
        var order: [String] = []
        var map: [String: [EffectEntry]] = [:]
        for e in catalog {
            if map[e.menu] == nil { order.append(e.menu) }
            map[e.menu, default: []].append(e)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func load() {
        guard let out = model.quietQuery("effect.list") as? [String: Any] else { items = []; return }
        if catalog.isEmpty, let cat = out["catalog"] as? [[String: Any]] {
            catalog = cat.compactMap { d in
                guard let id = jsonString(d["id"]) else { return nil }
                let menu = (d["menu"] as? [String])?.joined(separator: " › ") ?? jsonString(d["menu"]) ?? "Effects"
                return EffectEntry(id: id, label: jsonString(d["label"]) ?? id, menu: menu)
            }
        }
        let applied = (out["applied"] as? [[String: Any]])?.first
        let list = applied?["items"] as? [[String: Any]] ?? []
        items = list.compactMap { d in
            guard let raw = jsonNumber(d["index"]), let i = CommandForm.safeInt(raw) else { return nil }
            let fx = (d["effects"] as? [Any])?.count ?? CommandForm.safeInt(jsonNumber(d["effects"]) ?? 0) ?? 0
            return Item(index: i, kind: jsonString(d["kind"]) ?? "fill", effects: fx)
        }
    }
}
