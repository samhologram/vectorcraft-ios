import SwiftUI
@preconcurrency import VectorCraftKit

/// Desktop UI-only commands (`UI_COMMANDS`) mapped onto this model, tools, interactions and tool options.
extension DocumentModel {
    private static let zoomStep = 1.25

    /// UI-only desktop ids this model implements. Menus hide the others.
    nonisolated static let implementedUIIDs: Set<String> = [
        "window.panel", "window.panel.activate", "window.panel.close", "tool.select", "window.dock", "window.panels",
        "view.zoomIn", "view.zoomOut", "view.fitArtboard", "view.fitAll", "view.actualSize", "view.setZoom",
        "view.goToArtboard", "view.outline", "view.smartGuides", "view.snapToGrid", "view.snapToPoint",
        "view.boundingBox", "file.export.svg", "file.export.png", "file.export.pdf", "file.exportForScreens",
        "ui.paramDialog", "file.save",
    ]

    nonisolated static func implementsUI(_ id: String) -> Bool { implementedUIIDs.contains(id) }

    /// Runs a desktop UI-only command. Unknown ones set `lastError`; this never crashes.
    func runUI(_ id: String, _ params: [String: Any] = [:]) {
        switch id {
        case "window.panel", "window.panel.activate":
            guard let name = params["panel"] as? String else { lastError = "window.panel needs a panel id."; return }
            showPanel(named: name)
        case "window.panel.close":
            if narrowPanelLayout { phoneSheetPresented = false } else { inspectorVisible = false }
        case "window.dock", "window.panels":
            togglePanelVisibility()
        case "tool.select":
            if let tool = params["tool"] as? String { selectTool(tool) } else { lastError = "tool.select needs a tool id." }
        case "view.zoomIn":
            zoom(by: Self.zoomStep, around: viewCenter)
        case "view.zoomOut":
            zoom(by: 1 / Self.zoomStep, around: viewCenter)
        case "view.fitArtboard":
            fitArtboard()
        case "view.fitAll":
            fitAll()
        case "view.actualSize":
            setZoom(1)
        case "view.setZoom":
            guard let percent = (params["zoom"] as? NSNumber)?.doubleValue, percent.isFinite, percent > 0 else {
                lastError = "view.setZoom needs a zoom percentage."
                return
            }
            if let c = params["center"] as? [Any], c.count == 2,
               let x = (c[0] as? NSNumber)?.doubleValue, let y = (c[1] as? NSNumber)?.doubleValue,
               x.isFinite, y.isFinite {
                view.centerX = x
                view.centerY = y
            }
            setZoom(percent / 100)
        case "view.goToArtboard":
            goToArtboard(params["index"])
        case "view.outline":
            view.outline.toggle()
            renderTick += 1
        case "view.smartGuides":
            view.smartGuides.toggle()
        case "view.snapToGrid":
            view.snapToGrid.toggle()
        case "view.snapToPoint":
            view.snapToPoint.toggle()
        case "view.boundingBox":
            view.showBBox.toggle()
            overlayTick += 1
        case "file.export.svg", "file.export.png", "file.export.pdf", "file.exportForScreens":
            showExport = true
        case "ui.paramDialog":
            if let command = params["command"] as? String {
                pendingParams = (params["params"] as? [String: Any]) ?? [:]
                pendingCommand = command
            }
        case "file.save":
            setStatus("VectorCraft saves your document automatically.")
        default:
            lastError = "Not available on iPad and iPhone yet: \(CommandCatalog.shared.label(id))"
        }
    }

    // MARK: Panels

    /// `window.panel`: shows the named panel (id or label, any case).
    func showPanel(named name: String) {
        let catalog = CommandCatalog.shared
        let canonical = catalog.panels.first {
            $0.id.caseInsensitiveCompare(name) == .orderedSame || $0.label.caseInsensitiveCompare(name) == .orderedSame
        }?.id ?? name
        // A Window-menu invocation always reveals the requested panel. Closing it is a separate action.
        showDockPanel(canonical)
    }

    // MARK: Tools

    func selectTool(_ id: String) {
        let before = state.tool
        do {
            try handle.selectTool(id: id, view: view.viewParams())
        } catch {
            lastError = error.localizedDescription
            return
        }
        if before != id { previousTool = before }
        refresh()
        refreshToolOptions()
    }

    /// Pencil double-tap: back to the previously used tool.
    func selectPreviousTool() {
        if let previous = previousTool { selectTool(previous) }
    }

    func setToolOption(_ key: String, _ value: Any) {
        guard let json = Self.encodeValue(value) else {
            lastError = "Could not encode the value of \(key)."
            return
        }
        do {
            try handle.setToolOption(key: key, valueJson: json)
        } catch {
            lastError = error.localizedDescription
        }
        refreshToolOptions()
        overlayTick += 1
    }

    // MARK: Interactions (slider drags: one undo step)

    func beginDrag(_ label: String) {
        guard !sliderDragging else { return }
        interactionHistoryStart = state.historyId
        do {
            try handle.beginInteraction(label: label)
            sliderDragging = true
            setInteracting(true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Live preview of a command inside a drag (no undo step until `endDrag`).
    func preview(_ id: String, _ params: [String: Any]) {
        guard let json = Self.encode(params) else { return }
        do {
            _ = try handle.preview(id: id, paramsJson: json)
        } catch {
            if lastError == nil { lastError = error.localizedDescription }
        }
        state = handle.state()
        renderTick += 1
    }

    func endDrag() {
        guard sliderDragging else { return }
        sliderDragging = false
        do {
            try handle.commitInteraction()
        } catch {
            lastError = error.localizedDescription
        }
        setInteracting(false)
        refresh()
        if state.historyId != interactionHistoryStart { registerUndoStep(label: state.undoLabel) }
    }

    func cancelDrag() {
        guard sliderDragging else { return }
        sliderDragging = false
        do {
            try handle.cancelInteraction()
        } catch {
            lastError = error.localizedDescription
        }
        setInteracting(false)
        refresh()
    }

    func setInteracting(_ on: Bool) {
        guard isInteractingStorage != on else { return }
        isInteractingStorage = on
        if !on { renderTick += 1 }  // sharp render after the gesture
    }
}
