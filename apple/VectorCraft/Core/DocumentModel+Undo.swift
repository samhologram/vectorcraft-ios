import Foundation
@preconcurrency import VectorCraftKit

/// Undo integration.
///
/// The engine owns the real history. The scene `UndoManager` only mirrors it: every engine history step registers
/// one entry whose handler asks the engine to undo, and registers the symmetric redo inside it. That makes
/// Cmd-Z, the two-finger tap, shake-to-undo and the document's dirty state (autosave) work.
extension DocumentModel {
    func undo() {
        guard state.canUndo else { return }
        if let manager = undoManager, manager.canUndo {
            manager.undo()  // its handler performs the engine step
        } else {
            stepEngine(undo: true)
        }
    }

    func redo() {
        guard state.canRedo else { return }
        if let manager = undoManager, manager.canRedo {
            manager.redo()
        } else {
            stepEngine(undo: false)
        }
    }

    /// Registers one undo entry for the history step the engine just recorded. Never call for queries.
    func registerUndoStep(label: String?) {
        guard let manager = undoManager else { return }
        manager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.managerRequestedUndo() }
        }
        if let label, !label.isEmpty, !manager.isUndoing, !manager.isRedoing { manager.setActionName(label) }
    }

    /// Invoked by the UndoManager while it is undoing: step the engine, file the redo.
    private func managerRequestedUndo() {
        stepEngine(undo: true)
        guard let manager = undoManager else { return }
        manager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.managerRequestedRedo() }
        }
        if let label = state.redoLabel, !label.isEmpty { manager.setActionName(label) }
    }

    private func managerRequestedRedo() {
        stepEngine(undo: false)
        guard let manager = undoManager else { return }
        manager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.managerRequestedUndo() }
        }
        if let label = state.undoLabel, !label.isEmpty { manager.setActionName(label) }
    }

    private func stepEngine(undo: Bool) {
        do {
            _ = try (undo ? handle.undo() : handle.redo())
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }
}
