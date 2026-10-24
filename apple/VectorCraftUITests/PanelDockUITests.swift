import XCTest

/// Verifies the iPad inspector's reveal behavior, including showing an already selected tab.
@MainActor
final class PanelDockUITests: VectorCraftUITestCase {
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
