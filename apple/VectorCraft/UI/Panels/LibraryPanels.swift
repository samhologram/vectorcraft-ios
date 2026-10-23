import SwiftUI
import VectorCraftKit

/// Undo and redo with the engine's step labels.
struct HistoryPanel: View {
    let model: DocumentModel

    var body: some View {
        Form {
            Section("Next Undo") {
                Button {
                    model.undo()
                } label: {
                    Label(model.state.undoLabel ?? "Nothing to undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.state.canUndo)
                .accessibilityIdentifier("control.history.undo")
            }
            Section("Next Redo") {
                Button {
                    model.redo()
                } label: {
                    Label(model.state.redoLabel ?? "Nothing to redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!model.state.canRedo)
                .accessibilityIdentifier("control.history.redo")
            }
            Section {
                CommandButton(model: model, id: "edit.clearHistory", title: "Clear History", symbol: "trash")
            } footer: {
                Text("Two-finger tap undoes, three-finger tap redoes.")
            }
        }
        .accessibilityIdentifier("control.history")
    }
}

/// A list of named things from the document (symbols, brushes) with an action per row and "new" commands.
private struct NamedItemsPage: View {
    let model: DocumentModel
    let panelID: String
    let names: [String]
    let emptyTitle: String
    let emptySymbol: String
    let emptyMessage: String
    let rowSymbol: String
    let apply: (String) -> Void
    let footer: AnyView

    var body: some View {
        List {
            if names.isEmpty {
                PanelEmpty(title: emptyTitle, symbol: emptySymbol, message: emptyMessage)
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                    Button {
                        apply(name)
                    } label: {
                        Label { Text(verbatim: name).lineLimit(1) } icon: { Image(systemName: rowSymbol) }
                    }
                    .accessibilityIdentifier("control.\(panelID).item.\(i)")
                }
            }
            Section { footer }
        }
        .accessibilityIdentifier("control.\(panelID)")
    }
}

@MainActor private func infoNames(_ model: DocumentModel, category: String, key: String) -> [String] {
    guard let out = model.quietQuery("document.info", ["category": category]) as? [String: Any] else { return [] }
    if let a = out[key] as? [String] { return a }
    if let a = out[key] as? [[String: Any]] { return a.compactMap { jsonString($0["name"]) } }
    return []
}

struct SymbolsPanel: View {
    let model: DocumentModel
    @State private var names: [String] = []

    var body: some View {
        NamedItemsPage(model: model, panelID: "symbols", names: names, emptyTitle: "No Symbols", emptySymbol: "star",
                       emptyMessage: "Select art and choose New Symbol to make one.", rowSymbol: "star",
                       apply: { model.run("symbol.place", ["name": $0]) },
                       footer: AnyView(Group {
                           CommandButton(model: model, id: "symbol.new", title: "New Symbol from Selection…", symbol: "plus")
                           CommandButton(model: model, id: "symbol.breakLink", title: "Break Link to Symbol")
                       }))
        .task(id: model.state.historyId) { names = infoNames(model, category: "symbols", key: "symbols") }
    }
}

struct BrushesPanel: View {
    let model: DocumentModel
    @State private var names: [String] = []

    var body: some View {
        NamedItemsPage(model: model, panelID: "brushes", names: names, emptyTitle: "No Brushes", emptySymbol: "paintbrush",
                       emptyMessage: "Create a brush from selected art.", rowSymbol: "paintbrush",
                       apply: { model.run("brush.apply", ["name": $0]) },
                       footer: AnyView(Group {
                           CommandButton(model: model, id: "brush.new", title: "New Brush…", symbol: "plus")
                           CommandButton(model: model, id: "brush.remove", title: "Remove Brush Stroke")
                       }))
        .task(id: model.state.historyId) { names = infoNames(model, category: "brushes", key: "brushNames") }
    }
}

struct GraphicStylesPanel: View {
    let model: DocumentModel

    struct Style: Identifiable {
        let index: Int
        let name: String
        let fill: String?
        let stroke: String?
        var id: Int { index }
    }

    @State private var styles: [Style] = []

    var body: some View {
        Form {
            Section {
                if styles.isEmpty {
                    PanelEmpty(title: "No Graphic Styles", symbol: "paintpalette", message: "Select art and choose New Graphic Style.")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 10) {
                    ForEach(styles) { s in
                        Button {
                            model.run("graphicStyle.apply", ["name": s.name])
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    PaintChip(paint: s.fill, size: 40)
                                    PaintChip(paint: s.stroke, size: 40).opacity(s.stroke == nil || s.stroke == "none" ? 0 : 0.5)
                                }
                                Text(verbatim: s.name).font(.caption2).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(s.name)
                        .accessibilityIdentifier("control.graphicStyles.item.\(s.index)")
                    }
                }
            }
            Section {
                CommandButton(model: model, id: "graphicStyle.new", title: "New Graphic Style…", symbol: "plus")
                CommandButton(model: model, id: "graphicStyle.breakLink", title: "Break Link to Graphic Style")
            }
        }
        .task(id: model.state.historyId) { load() }
        .accessibilityIdentifier("control.graphicStyles")
    }

    private func load() {
        guard let out = model.quietQuery("graphicStyle.list") as? [String: Any], let list = out["styles"] as? [[String: Any]] else { styles = []; return }
        styles = list.enumerated().map { i, d in
            Style(index: i, name: jsonString(d["name"]) ?? "", fill: jsonString(d["fill"]), stroke: jsonString(d["stroke"]))
        }
    }
}
