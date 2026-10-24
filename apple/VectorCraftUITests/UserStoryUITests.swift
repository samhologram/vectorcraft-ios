import XCTest

@MainActor
final class UserStoryUITests: VectorCraftUITestCase {
    /// Organize artwork by hiding a layer, then recover it with undo. Uses the dock on iPad and a sheet on iPhone.
    func testLayerVisibilityUndoRedoAndPanelReopenPortrait() {
        XCUIDevice.shared.orientation = .portrait
        launchDemo(dark: false)
        openNewDocument()
        XCTAssertTrue(element("demoReady").exists, "The story requires seeded artwork")
        defer { flushNotes("layer-story-notes") }
        var cause = ""
        XCTAssertNotNil(openPanel("layers", cause: &cause), "Layers must open: \(cause)")
        let toggles = prefixQuery("layer.").allElementsBoundByIndex.filter {
            $0.identifier.hasSuffix(".visible") && canTap($0)
        }
        guard let toggle = toggles.first else { XCTFail("No artwork layer has a reachable visibility control"); return }
        let id = toggle.identifier
        let original = toggle.label
        toggle.tap()
        let changed = NSPredicate { _, _ in self.element(id).label != original }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: changed, evaluatedWith: nil)], timeout: 5), .completed)
        let edited = element(id).label
        closePanelIfOpen()
        XCTAssertTrue(tapUndo(), "Hiding artwork must be undoable")
        XCTAssertNotNil(openPanel("layers", cause: &cause), cause)
        XCTAssertEqual(element(id).label, original, "Undo must restore the layer's visibility")
        closePanelIfOpen()
        XCTAssertTrue(tapRedo(), "Visibility must support redo")
        XCTAssertNotNil(openPanel("layers", cause: &cause), cause)
        XCTAssertEqual(element(id).label, edited, "Redo must restore the visibility edit")
        XCTAssertTrue(canTap(element(id)), "Reopened layer controls must remain reachable")
        if !isPad { XCTAssertNotNil(hit("panel.close"), "iPhone panels must have a reachable sheet dismissal") }
        note("Layer visibility edited, undone, redone and verified after reopening Layers on \(isPad ? "iPad" : "iPhone")")
    }

    func testDrawRectangleUndoRedoPortrait() {
        XCUIDevice.shared.orientation = .portrait
        launchDemo(dark: true)
        openNewDocument()
        XCTAssertTrue(element("demoReady").exists)
        defer { flushNotes("draw-story-notes") }
        closePanelIfOpen()
        let before = undoLabel
        XCTAssertNil(selectTool("rectangle", group: "rectangle", multi: true), "Rectangle tool must be selectable")
        canvasDrag(from: (0.3, 0.3), to: (0.6, 0.55))
        XCTAssertNotEqual(undoLabel, before, "Drawing a rectangle must create an edit")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Drawing must not leave an engine error")
        let drawn = undoLabel
        XCTAssertTrue(tapUndo())
        XCTAssertEqual(undoLabel, before, "A single Undo must remove the completed rectangle gesture")
        XCTAssertTrue(tapRedo())
        XCTAssertEqual(undoLabel, drawn, "Redo must restore the rectangle edit")
        XCTAssertTrue(tap("control.fullscreen"))
        XCTAssertTrue(element("control.fullscreen.exit").waitForExistence(timeout: 5))
        XCTAssertFalse(element("inspector").exists, "Full screen must hide the dock or sheet")
        XCTAssertTrue(element("canvas").exists)
        XCTAssertTrue(tap("control.fullscreen.exit"))
        XCTAssertTrue(element("undo").waitForExistence(timeout: 5))
    }
}
