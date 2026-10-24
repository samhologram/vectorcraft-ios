import XCTest

/// Verifies the iPad inspector's reveal behavior, including showing an already selected tab.
@MainActor
final class PanelDockUITests: VectorCraftUITestCase {
    func testToolbarSidebarRestoresSelectedPanel() {

        continueAfterFailure = false
        defer {
            let evidence = XCTAttachment(string: app.debugDescription)
            evidence.name = "sidebar-toggle-hierarchy"; evidence.lifetime = .keepAlways; add(evidence)
        }
        func waitState(_ message: String, _ check: @escaping () -> Bool) {
            let predicate = NSPredicate { _, _ in check() }
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: nil)], timeout: 8), .completed, message)
        }

        launchDemo(dark: false)
        openNewDocument()
        XCTAssertTrue(element("canvas").waitForExistence(timeout: 10), "Fixture: drawing must open")
        var cause = ""
        XCTAssertNotNil(openPanel("layers", cause: &cause), "Fixture: Layers must open: \(cause)")
        func shown() -> Bool {
            if isPad { return element("panelBody.layers").isHittable && hit("panel.layers") != nil }
            return element("panelTitle").exists && element("panelTitle").label == "Layers" && hit("panel.close") != nil
        }
        waitState("Layers must be foreground and reachable", shown)
        XCTAssertTrue(tap("toggleInspector"), "Toolbar must hide panels")
        waitState("Panels must disappear", { !self.element("inspector").isHittable })
        XCTAssertTrue(tap("toggleInspector"), "Toolbar must restore panels")
        waitState("Restored presentation must preserve Layers", shown)
        XCTAssertTrue(tap("toggleInspector"))
        waitState("Panels must hide before explicit menu reopen", { !self.element("inspector").isHittable })
        XCTAssertNotNil(openPanel("layers", cause: &cause), "Opening hidden Layers must reveal it: \(cause)")
        waitState("Explicit reopen must reveal Layers", shown)
    }

    func testShowCollapseReopenAndHide() throws {
        try XCTSkipUnless(isPad, "The stacked inspector is an iPad layout")
        launchDemo(dark: false)
        openNewDocument()
        let id = "graphicStyles"

        func addPanel() {
            XCTAssertTrue(tap("control.panelMenu"), "The panel Add menu is missing")
            guard let choice = hit("panel.\(id)") else {
                XCTFail("The Add menu did not expose \(id)")
                return
            }
            choice.tap()
            var visibleTab: XCUIElement?
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline, visibleTab == nil {
                visibleTab = hit("panel.\(id)")
                if visibleTab == nil { pause(0.2) }
            }
            guard let tab = visibleTab else {
                XCTFail("The new tab was not scrolled into view")
                return
            }
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "The new tab was not added")
            XCTAssertTrue(canTap(tab), "The new tab was not scrolled into view")
            XCTAssertTrue(element("panelBody.\(id)").exists, "The new panel did not expand")
        }

        addPanel()
        // The second Add must reveal this same tab, not toggle the panel closed.
        addPanel()

        XCTAssertTrue(tap("panelHeader.\(id)"), "Collapse control is missing")
        XCTAssertFalse(element("panelBody.\(id)").exists, "The panel did not collapse")
        addPanel()

        XCTAssertTrue(tap("panelActions.\(id)"), "The panel action menu is missing")
        XCTAssertTrue(tap("panelClose.\(id)"), "The Close action is missing")
        XCTAssertFalse(element("panelBody.\(id)").exists, "The panel body remained after Close")
        addPanel()
    }
}
