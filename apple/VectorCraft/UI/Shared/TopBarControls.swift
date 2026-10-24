import SwiftUI
import VectorCraftKit

/// Undo / redo buttons for the top bar (`undo`, `redo`). They go through the model, which mirrors the engine's
/// history on the scene's `UndoManager`.
struct UndoRedoButtons: View {
    let model: DocumentModel

    var body: some View {
        Button {
            model.undo()
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .disabled(!model.state.canUndo)
        .accessibilityLabel(model.state.undoLabel.map { "Undo \($0)" } ?? "Undo")
        .accessibilityIdentifier("undo")
        Button {
            model.redo()
        } label: {
            Label("Redo", systemImage: "arrow.uturn.forward")
        }
        .disabled(!model.state.canRedo)
        .accessibilityLabel(model.state.redoLabel.map { "Redo \($0)" } ?? "Redo")
        .accessibilityIdentifier("redo")
    }
}

/// Export button (`export`).
struct ExportButton: View {
    let model: DocumentModel

    var body: some View {
        Button {
            model.showExport = true
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("export")
    }
}

/// Opens the command palette (`commandPalette`).
struct PaletteButton: View {
    let model: DocumentModel

    var body: some View {
        Button {
            model.showCommandPalette = true
        } label: {
            Label("Command Palette", systemImage: "magnifyingglass")
        }
        .accessibilityIdentifier("commandPalette")
    }
}

/// The panels (Window) menu: every desktop panel, the hand-built ones first.
struct PanelsMenu: View {
    let model: DocumentModel

    var body: some View {
        Menu {
            PanelsMenuContent(model: model)
        } label: {
            Label("Panels", systemImage: "rectangle.3.group")
        }
        .accessibilityIdentifier("menu.panels")
    }
}

struct PanelsMenuContent: View {
    let model: DocumentModel

    var body: some View {
        let built = Set(Panel.allCases.map(\.rawValue))
        let all = CommandCatalog.shared.panels
        let main = all.filter { built.contains($0.id) }
        let rest = all.filter { !built.contains($0.id) }
        ForEach(main, id: \.id) { p in item(p) }
        if !rest.isEmpty {
            Divider()
            Menu("More Panels") {
                ForEach(rest, id: \.id) { p in item(p) }
            }
            .accessibilityIdentifier("menu.panels.more")
        }
    }

    private func item(_ p: PanelInfo) -> some View {
        Button {
            model.showPanel(named: p.id)
        } label: {
            Label(p.label, systemImage: CommandCatalog.shared.symbol(forPanel: p.id))
        }
        .accessibilityIdentifier("menu.panels.\(p.id)")
    }
}

/// The "…" overflow menu with the whole desktop menu bar. On narrow bars it also carries the palette,
/// panels and export (the degradation order: full bar, then these move here).
struct OverflowMenu: View {
    let model: DocumentModel
    var includesActions = false

    var body: some View {
        Menu {
            if includesActions {
                Button {
                    model.showCommandPalette = true
                } label: {
                    Label("Command Palette", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("commandPalette.menu")
                Button {
                    model.showExport = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("export.menu")
                Menu {
                    PanelsMenuContent(model: model)
                } label: {
                    Label("Panels", systemImage: "rectangle.3.group")
                }
                .accessibilityIdentifier("menu.panels")
                Divider()
            }
            ForEach(MenuLayout.titles, id: \.self) { title in
                Menu(title) {
                    CommandMenuContent(model: model, title: title)
                }
                .accessibilityIdentifier("menu.\(title)")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("menu.more")
    }
}
