import Foundation
@preconcurrency import VectorCraftKit

/// Launch-argument driven demo (`-VectorCraftDemo`) used by the screenshot pipeline and the UI tests.
///
/// A NEW document is filled through the same engine commands the UI uses (shapes, paint, a gradient, type), then
/// the artboard is fitted and the `demoReady` marker (`isDemoReady`) is raised once the canvas shows the art.
@MainActor
enum DemoContent {
    /// Steps that failed, for the log. Failures never surface as alerts in demo mode.
    private(set) static var failures: [String] = []

    static func seed(_ model: DocumentModel) {
        guard !model.demoSeeded else { return }
        model.demoSeeded = true

        // Background: a deep blue-to-teal gradient over the whole artboard.
        if let bg = shape(model, "shape.rectangle", ["x": 0, "y": 0, "width": 1080, "height": 1080]) {
            noStroke(model, bg)
            step(model, "paint.setFill", ["ids": [bg], "gradient": [
                "kind": "linear", "angle": 60,
                "stops": [["offset": 0, "color": "#14213d"], ["offset": 1, "color": "#0b7a75"]],
            ] as [String: Any]])
        }
        // Coral circle.
        if let circle = shape(model, "shape.ellipse", ["x": 130, "y": 330, "width": 400, "height": 400]) {
            noStroke(model, circle)
            step(model, "paint.setFill", ["ids": [circle], "color": "#ff7a59"])
        }
        // Golden star.
        if let star = shape(model, "shape.star", ["cx": 770, "cy": 400, "radius1": 230, "radius2": 100, "points": 5, "rotation": -18]) {
            noStroke(model, star)
            step(model, "paint.setFill", ["ids": [star], "color": "#ffd166"])
        }
        // Mint rounded rectangle with a white outline.
        if let card = shape(model, "shape.rectangle", ["x": 250, "y": 720, "width": 580, "height": 220, "radius": 48]) {
            step(model, "paint.setFill", ["ids": [card], "color": "#06d6a0"])
            step(model, "paint.setStroke", ["ids": [card], "color": "#ffffff"])
        }
        // Title.
        if let title = shape(model, "text.create", ["x": 120, "y": 200, "text": "VectorCraft", "size": 120]) {
            step(model, "paint.setFill", ["ids": [title], "color": "#ffffff"])
        }

        _ = model.execute("select.none")
        model.lastError = nil
        model.selectTool("selection")
        model.fitArtboard()
        model.refresh()
        // The marker is raised when the canvas shows its first frame; this covers a run with no canvas.
        Task { [weak model] in
            try? await Task.sleep(for: .seconds(2))  // cancellation only ends the wait early
            model?.isDemoReady = true
        }
    }

    private static func noStroke(_ model: DocumentModel, _ id: UInt64) {
        step(model, "paint.setStroke", ["ids": [id], "none": true])
    }

    /// Runs a creation command and returns the new node's id.
    private static func shape(_ model: DocumentModel, _ id: String, _ params: [String: Any]) -> UInt64? {
        guard let result = model.execute(id, params), let n = (result["id"] as? NSNumber)?.uint64Value else {
            failures.append("\(id): \(model.lastError ?? "no id")")
            model.lastError = nil
            return nil
        }
        return n
    }

    private static func step(_ model: DocumentModel, _ id: String, _ params: [String: Any]) {
        if model.execute(id, params) == nil {
            failures.append("\(id): \(model.lastError ?? "failed")")
            model.lastError = nil
        }
    }
}

extension DocumentModel {
    /// `-VectorCraftDemo`: shapes, a star, a gradient fill and type, made through commands. Idempotent.
    func seedDemo() { DemoContent.seed(self) }
}
