import XCTest

/// Smoke scenario in dark and light: new document, demo ready, panels, a tool drag on the canvas, undo / redo, the
/// overflow menu and one command from it. Missing elements are notes (`-notes` attachment); only a missing window,
/// a missing document or a crash fails.
@MainActor
final class VectorCraftUITests: VectorCraftUITestCase {
    func testSmokeDark() throws { try scenario(dark: true) }
    func testSmokeLight() throws { try scenario(dark: false) }

    private func scenario(dark: Bool) throws {
        launchDemo(dark: dark)
        continueAfterFailure = true
        defer { flushNotes() }
        openNewDocument()
        guard element("canvas").exists else { return }

        // The demo art is there: undo is enabled (demo seeding went through commands).
        if !canUndo { note("undo disabled after demo seeding: the demo document looks empty") }
        if element("demoReady").exists == false { note("demoReady marker missing") }

        // Panels.
        for panel in ["properties", "layers"] {
            var cause = ""
            if let route = openPanel(panel, cause: &cause) {
                let controls = exists(prefix: "control.\(panel)")
                if !controls { note("panel.\(panel): opened via \(route) but no control.\(panel).* content") }
                if panel == "layers", !exists(prefix: "layer.") { note("panel.layers: no layer.<id> rows after the demo seeding") }
            } else {
                note("panel.\(panel): not reachable (\(cause))")
            }
            dismissStrays()
        }
        closePanelIfOpen()

        // Pick the rectangle tool and draw.
        let undoBefore = undoLabel
        if let cause = selectTool("rectangle", group: "rectangle", multi: true) {
            note("tool.rectangle: \(cause)")
        }
        canvasDrag(from: (0.3, 0.3), to: (0.6, 0.55))
        if undoLabel == undoBefore { note("rectangle drag: the undo history did not change") }
        XCTAssertEqual(app.state, .runningForeground, "the app crashed while drawing")

        // Undo / redo buttons.
        if canUndo {
            let beforeUndo = undoLabel
            tapUndo()
            if canRedo { tapRedo() } else { note("redo not enabled after undo") }
            if undoLabel != beforeUndo { note("undo label differs after undo + redo: '\(beforeUndo)' vs '\(undoLabel)'") }
        } else {
            note("undo is disabled after drawing")
        }

        // The overflow menu and one command (the first enabled entry of the Select menu).
        if let cause = openOverflowPath(["Select"]) {
            note("overflow Select menu: \(cause)")
        } else {
            let entry = prefixQuery("command.").allElementsBoundByIndex.first { $0.exists && $0.isEnabled && canTap($0) }
            if let entry {
                let id = entry.identifier
                entry.tap()
                pause(1)
                let sheet = resolveSheet()
                note("ran \(id): \(sheet.text.isEmpty ? "no sheet" : sheet.text)")
                for a in dismissStrays() { note("\(id): alert \(a)") }
            } else {
                note("no enabled command in the Select menu")
                closeMenus()
            }
        }
        XCTAssertEqual(app.state, .runningForeground, "the app crashed after a menu command")
    }
}
