import SwiftUI
@preconcurrency import VectorCraftKit

/// The canvas view: size, zoom, pan, fit; tool events from the canvas.
extension DocumentModel {
    private static let fitMargin = 32.0

    var viewCenter: CGPoint { CGPoint(x: view.viewSize.width / 2, y: view.viewSize.height / 2) }

    /// Called by the canvas when its size or screen scale changes.
    func setViewSize(_ size: CGSize, pixelScale: Double) {
        guard size.width.isFinite, size.height.isFinite, size.width > 1, size.height > 1 else { return }
        if view.viewSize != size { view.viewSize = size }
        if view.pixelScale != pixelScale { view.pixelScale = pixelScale }
        if pendingFit {
            pendingFit = false
            fitArtboard()
        }
    }

    private func activeArtboardRect() -> CGRect? {
        let boards = state.artboards
        let active = boards.first { $0.index == state.activeArtboard } ?? boards.first
        return active.map(Self.rect)
    }

    private static func rect(_ a: ArtboardInfo) -> CGRect {
        CGRect(x: a.rect.x, y: a.rect.y, width: a.rect.width, height: a.rect.height)
    }

    private func fit(_ rect: CGRect) {
        guard view.hasSize, rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite else { return }
        let availW = max(view.viewSize.width - 2 * Self.fitMargin, 40)
        let availH = max(view.viewSize.height - 2 * Self.fitMargin, 40)
        view.zoom = ViewTransform.clampedZoom(min(Double(availW) / Double(rect.width), Double(availH) / Double(rect.height)))
        view.centerX = Double(rect.midX)
        view.centerY = Double(rect.midY)
        renderTick += 1
    }

    /// Fits the active artboard in the window (`view.fitArtboard`). Before the canvas has a size it is deferred.
    func fitArtboard() {
        guard view.hasSize else { pendingFit = true; return }
        if let rect = activeArtboardRect() { fit(rect) }
    }

    /// Fits all artboards (`view.fitAll`).
    func fitAll() {
        guard view.hasSize else { pendingFit = true; return }
        let rects = state.artboards.map(Self.rect)
        guard var union = rects.first else { return }
        for r in rects.dropFirst() { union = union.union(r) }
        fit(union)
    }

    func setZoom(_ zoom: Double) {
        view.zoom = ViewTransform.clampedZoom(zoom)
        renderTick += 1
    }

    /// Zooms by `factor` keeping the document point under `viewPoint` fixed.
    func zoom(by factor: Double, around viewPoint: CGPoint) {
        guard factor.isFinite, factor > 0, view.hasSize else { return }
        let anchor = view.toDocument(viewPoint)
        let newZoom = ViewTransform.clampedZoom(view.zoom * factor)
        view.zoom = newZoom
        view.centerX = Double(anchor.x) - (Double(viewPoint.x) - Double(view.viewSize.width) / 2) / newZoom
        view.centerY = Double(anchor.y) - (Double(viewPoint.y) - Double(view.viewSize.height) / 2) / newZoom
        renderTick += 1
    }

    /// Pans by `delta` view points (the content follows the fingers).
    func pan(by delta: CGSize) {
        guard view.zoom > 0, delta.width.isFinite, delta.height.isFinite else { return }
        view.centerX -= Double(delta.width) / view.zoom
        view.centerY -= Double(delta.height) / view.zoom
        renderTick += 1
    }

    /// `view.goToArtboard`: index number or "first" | "previous" | "next" | "last".
    func goToArtboard(_ value: Any?) {
        let boards = state.artboards
        guard !boards.isEmpty else { return }
        let current = Int(state.activeArtboard)
        var target = current
        if let n = (value as? NSNumber)?.intValue {
            target = n
        } else if let s = value as? String {
            switch s {
            case "first": target = 0
            case "previous": target = current - 1
            case "next": target = current + 1
            case "last": target = boards.count - 1
            default: break
            }
        }
        target = min(max(target, 0), boards.count - 1)
        view.artboard = UInt32(target)
        if let board = boards.first(where: { Int($0.index) == target }) { fit(Self.rect(board)) }
    }

    // MARK: Tool events (from the canvas)

    /// A pointer event in document coordinates. kind: "down", "drag", "up", "move", "doubleClick".
    func pointer(_ kind: String, atDocument p: CGPoint, pressure: Float = 1, modifiers: Modifiers = .none) {
        guard p.x.isFinite, p.y.isFinite else { return }
        let before = state.historyId
        do {
            let requests = try handle.pointer(
                kind: kind, x: Double(p.x), y: Double(p.y), mods: modifiers, pressure: pressure, view: view.viewParams())
            handleRequests(requests)
        } catch {
            if lastError == nil { lastError = error.localizedDescription }
        }
        switch kind {
        case "down", "drag":
            setInteracting(true)
            renderTick += 1
            overlayTick += 1
        case "move":
            overlayTick += 1
        default:  // "up", "doubleClick"
            setInteracting(false)
            finishMutation(id: "tool.pointer", historyBefore: before)
        }
    }

    /// A key for the active tool: "enter", "escape", "backspace", "delete", arrows, "tab"…
    func toolKey(_ key: String, modifiers: Modifiers = .none) {
        let before = state.historyId
        do {
            handleRequests(try handle.toolKey(key: key, mods: modifiers, view: view.viewParams()))
        } catch {
            if lastError == nil { lastError = error.localizedDescription }
        }
        finishMutation(id: "tool.key", historyBefore: before)
    }

    /// Typed text for a Type tool that is editing (`state.toolWantsText`).
    func toolText(_ text: String) {
        let before = state.historyId
        do {
            handleRequests(try handle.toolText(text: text, view: view.viewParams()))
        } catch {
            if lastError == nil { lastError = error.localizedDescription }
        }
        finishMutation(id: "tool.text", historyBefore: before)
    }

    /// One tick for tools that animate while the pointer is held (spray, blob…).
    func toolTick(_ dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        do {
            handleRequests(try handle.toolTick(dt: dt, view: view.viewParams()))
        } catch {
            if lastError == nil { lastError = error.localizedDescription }
        }
        renderTick += 1
        overlayTick += 1
    }

    var toolWantsTicks: Bool { handle.toolWantsTicks() }

    /// Overlays (tool previews, handles) for the current view.
    func overlays() -> [OverlayItem] { handle.overlays(view: view.viewParams()) }

    /// Called by the canvas once the first image of the document is on screen.
    func canvasDidPresent() {
        guard !canvasPresented else { return }
        canvasPresented = true
        if demoSeeded { isDemoReady = true }
    }
}
