import SwiftUI
import VectorCraftKit

private struct PendingCommand: Identifiable {
    let id: String
}

/// Entry view of a document: picks the iPad or iPhone layout, publishes the model to the menu bar, and hosts
/// every sheet and alert.
struct EditorRootView: View {
    @Bindable var model: DocumentModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.undoManager) private var undoManager

    @State private var ui = EditorUIState()
    @State private var commandItem: PendingCommand?
    @State private var paletteShown = false
    @State private var exportShown = false

    var body: some View {
        GeometryReader { geo in
            let pad = horizontalSizeClass == .regular && geo.size.width >= 700
            Group {
                if model.isFullscreen {
                    FullscreenCanvas(model: model)
                } else if pad {
                    PadEditorView(model: model)
                } else {
                    PhoneEditorView(model: model)
                }
            }
            .toolbar { EditorToolbar(model: model, pad: pad) }
            .toolbar(model.isFullscreen ? .hidden : .automatic, for: .navigationBar)
            .onChange(of: pad, initial: true) { _, isPad in ui.narrow = !isPad }
        }
        .statusBarHidden(model.isFullscreen)
        .persistentSystemOverlays(model.isFullscreen ? .hidden : .automatic)
        .animation(.default, value: model.isFullscreen)
        .environment(ui)
        .focusedSceneValue(\.documentModel, model)
        .background { ToolShortcutButtons(model: model) }
        .overlay(alignment: .topLeading) {
            if model.isDemoReady {
                // Marker for UI tests: present once demo seeding finished.
                Color.clear
                    .frame(width: 2, height: 2)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityLabel("Demo ready")
                    .accessibilityIdentifier("demoReady")
            }
        }
        .overlay(alignment: .top) {
            if let message = model.statusMessage {
                Text(verbatim: message)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .accessibilityIdentifier("status")
            }
        }
        .animation(.default, value: model.statusMessage)
        .onChange(of: model.activeTool, initial: true) { _, tool in ui.noteActiveTool(tool) }
        .onAppear {
            if model.undoManager == nil { model.undoManager = undoManager }
        }
        .onChange(of: undoManager) { _, new in model.undoManager = new }
        // Sheets: shown after the panel sheet has closed, so presentations never collide.
        .sheet(item: $commandItem, onDismiss: { model.pendingCommand = nil; model.pendingParams = [:] }) { item in
            CommandSheet(model: model, commandID: item.id, prefill: model.pendingParams)
        }
        .sheet(isPresented: $paletteShown, onDismiss: { model.showCommandPalette = false }) {
            CommandPaletteView(model: model)
        }
        .sheet(isPresented: $exportShown, onDismiss: { model.showExport = false }) {
            ExportSheet(model: model)
        }
        .onChange(of: model.pendingCommand, initial: true) { _, new in
            if let new {
                presentAfterPanel { commandItem = PendingCommand(id: new) }
            } else {
                commandItem = nil
            }
        }
        .onChange(of: model.showCommandPalette, initial: true) { _, on in
            if on { presentAfterPanel { paletteShown = true } } else { paletteShown = false }
        }
        .onChange(of: model.showExport, initial: true) { _, on in
            if on { presentAfterPanel { exportShown = true } } else { exportShown = false }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { model.lastError = nil }
                .accessibilityIdentifier("errorAlert.ok")
        } message: {
            Text(verbatim: model.lastError ?? "")
                .accessibilityIdentifier("errorAlert")
        }
    }

    /// The panel sheet may be up; close it, wait for the dismissal, then present.
    private func presentAfterPanel(_ action: @escaping @MainActor () -> Void) {
        if ui.narrow && model.inspectorVisible {
            model.inspectorVisible = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                action()
            }
        } else {
            action()
        }
    }
}

/// Top bar: undo / redo, panels, command palette, export, overflow. On narrow bars the palette, panels and export
/// move into the overflow menu.
struct EditorToolbar: ToolbarContent {
    let model: DocumentModel
    let pad: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            UndoRedoButtons(model: model)
            FullscreenButton(model: model)
            if pad {
                PanelsMenu(model: model)
                PaletteButton(model: model)
                ExportButton(model: model)
            }
            OverflowMenu(model: model, includesActions: !pad)
        }
    }
}

/// Zero-size, invisible buttons that give a hardware keyboard the desktop's single-key tool shortcuts. `opacity(0)`
/// rather than `hidden()` (a hidden button gets no key equivalent). Absent while a Type tool is editing text, so
/// letters reach the text.
private struct ToolShortcutButtons: View {
    let model: DocumentModel

    private struct Item: Identifiable {
        let id: String
        let label: String
        let shortcut: ParsedShortcut
    }

    private static let items: [Item] = {
        CommandCatalog.shared.toolGroups.flatMap { $0.tools }.compactMap { t in
            guard let s = parseShortcut(t.shortcut), !s.modifiers.contains(.command) else { return nil }
            return Item(id: t.id, label: t.label, shortcut: s)
        }
    }()

    var body: some View {
        if !model.state.toolWantsText {
            Group {
                ForEach(Self.items) { item in
                    Button(item.label) { model.selectTool(item.id) }
                        .keyboardShortcut(item.shortcut.key, modifiers: item.shortcut.modifiers)
                }
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Canvas-only layout (View > Full Screen Canvas, ⌃⌘F): the canvas keeps its gestures and Pencil drawing; one small
/// floating glass button in a corner, inside the safe area, or Esc returns to the standard layout.
private struct FullscreenCanvas: View {
    let model: DocumentModel

    var body: some View {
        CanvasView(model: model)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button {
                    model.isFullscreen = false
                } label: {
                    Label("Exit Full Screen", systemImage: "arrow.down.right.and.arrow.up.left")
                        .labelStyle(.iconOnly)
                        .padding(10)
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.escape, modifiers: [])
                .padding(12)
                .accessibilityIdentifier("control.fullscreen.exit")
            }
    }
}

/// Top-bar button that enters the canvas-only layout (`control.fullscreen`).
struct FullscreenButton: View {
    let model: DocumentModel

    var body: some View {
        Button {
            model.isFullscreen = true
        } label: {
            Label("Full Screen Canvas", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .accessibilityIdentifier("control.fullscreen")
    }
}
