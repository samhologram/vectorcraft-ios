import XCTest

/// Picks every tool of the bridge's tool catalog (`TourCatalog.tools`, generated) through its group button and flyout
/// (`toolGroup.<first>` then `tool.<id>`), performs a gesture on the `canvas` and undoes. Only a crash fails;
/// misses are in the `-tour-summary` attachment.
@MainActor
final class ToolTourUITests: TourTestCase {
    func testToolsPortrait() throws { try tour(landscape: false) }
    func testToolsLandscape() throws { try tour(landscape: true) }

    private enum Gesture { case drag, clicks, text, tap }

    private func gesture(for tool: String) -> Gesture {
        switch tool {
        case "type", "areaType", "typeOnPath", "verticalType", "verticalAreaType", "verticalTypeOnPath", "touchType":
            return .text
        case "pen", "curvature", "addAnchor", "deleteAnchor", "anchorPoint", "perspectiveGrid", "polygonLasso":
            return .clicks
        case "eyedropper", "magicWand", "livePaintBucket", "livePaintSelection", "mesh", "measure":
            return .tap
        default:
            return .drag
        }
    }

    private func tour(landscape: Bool) throws {
        startTour(name: "tools", landscape: landscape)
        defer { attachSummary(); flushNotes() }
        XCTAssertFalse(TourCatalog.tools.isEmpty, "TourCatalog.tools is empty: regenerate it (run-ui-tests.sh --regen-lists)")
        extraSummaryLines.append("catalog tools: \(TourCatalog.tools.count) in \(Set(TourCatalog.tools.map(\.group)).count) groups")
        for tool in TourCatalog.tools {
            if let only, !only.contains(tool.id) { continue }
            if let limit, items.count >= limit { break }
            visit(tool)
        }
    }

    private func visit(_ tool: TourCatalog.Tool) {
        let name = "tool.\(tool.id)"
        dismissStrays()
        closePanelIfOpen()
        guard element("canvas").exists else {
            record(name, reached: false, cause: "no-canvas", "the document canvas is not on screen")
            _ = alive(name)
            return
        }
        let undoBefore = undoLabel
        // Give selection-based tools something to work on: Select All with the selection tool (hardware-keyboard
        // shortcut; harmless when it does nothing).
        if tool.id != "selection", let selection = hit("toolGroup.selection") {
            selection.tap()
            pause(0.3)
            app.typeKey("a", modifierFlags: .command)
            pause(0.3)
        }
        if let cause = selectTool(tool.id, group: tool.group, multi: tool.groupSize > 1) {
            let kind = cause.split(separator: ":").first.map(String.init) ?? cause
            record(name, reached: false, cause: kind, cause)
            _ = alive(name)
            return
        }
        var details: [String] = ["picked via toolGroup.\(tool.group)\(tool.groupSize > 1 ? " flyout" : "")"]
        switch gesture(for: tool.id) {
        case .drag:
            canvasDrag(from: (0.3, 0.3), to: (0.65, 0.55))
            canvasDrag(from: (0.65, 0.55), to: (0.4, 0.7))
        case .clicks:
            canvasTap((0.3, 0.3))
            canvasTap((0.6, 0.3))
            canvasDrag(from: (0.6, 0.6), to: (0.4, 0.7))
        case .tap:
            canvasTap((0.5, 0.45))
        case .text:
            canvasTap((0.35, 0.4))
            pause(0.6)
            if app.keyboards.count > 0 {
                app.typeText("Tour")
                details.append("typed text")
            } else {
                details.append("no keyboard after tapping with a type tool")
            }
        }
        pause(0.8)
        let changed = undoLabel != undoBefore
        details.append("history changed=\(changed)")
        let alerts = dismissStrays()
        for a in alerts { note("\(name): alert: \(a)") }
        guard alive(name) else { return }
        if app.keyboards.count > 0 { app.keyboards.buttons["return"].firstMatch.tap() }
        recover(undoLabelBefore: undoBefore)
        if !alerts.isEmpty {
            record(name, reached: false, cause: "engine-refused", "ALERTS=" + alerts.joined(separator: " || ") + "; " + details.joined(separator: "; "))
        } else {
            // Tools that legitimately create nothing on an empty gesture (select, view tools) are still "reached".
            record(name, reached: true, details.joined(separator: "; "))
        }
    }
}
