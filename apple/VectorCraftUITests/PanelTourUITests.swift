import XCTest

/// Opens every panel of the bridge's panel catalog (`TourCatalog.panels`, generated) through the real UI (panel
/// switcher, "more" menu or the Window menu), checks the panel title, acts on its first buttons and returns to a
/// usable state. Only a crash fails; misses are in the `-tour-summary` attachment.
@MainActor
final class PanelTourUITests: TourTestCase {
    func testPanelsPortrait() throws { try tour(landscape: false) }
    func testPanelsLandscape() throws { try tour(landscape: true) }

    private func tour(landscape: Bool) throws {
        startTour(name: "panels", landscape: landscape)
        defer { attachSummary(); flushNotes() }
        XCTAssertFalse(TourCatalog.panels.isEmpty, "TourCatalog.panels is empty: regenerate it (run-ui-tests.sh --regen-lists)")
        extraSummaryLines.append("catalog panels: \(TourCatalog.panels.count)")
        for panel in TourCatalog.panels {
            if let only, !only.contains(panel.id) { continue }
            if let limit, items.count >= limit { break }
            visit(panel)
        }
    }

    /// Buttons worth pressing inside an open panel: identifiers `control.<id>.*` and `command.*`, buttons only
    /// (sliders and text fields are left alone), never the sheet / close controls.
    private func actionTargets(panel: String) -> [XCUIElement] {
        let predicate = NSPredicate(format: "(identifier BEGINSWITH %@ OR identifier BEGINSWITH 'command.') AND NOT identifier BEGINSWITH 'commandSheet'", "control.\(panel).")
        var out: [XCUIElement] = []
        for e in app.buttons.matching(predicate).allElementsBoundByIndex where e.exists && e.isEnabled && canTap(e) {
            out.append(e)
            if out.count >= 2 { break }
        }
        return out
    }

    private func visit(_ panel: TourCatalog.Panel) {
        let name = "panel.\(panel.id)"
        dismissStrays()
        let undoBefore = undoLabel
        var cause = ""
        guard let route = openPanel(panel.id, cause: &cause) else {
            record(name, reached: false, cause: cause.isEmpty ? "missing-identifier" : cause, "panel \(panel.id) could not be opened")
            dismissStrays()
            _ = alive(name)
            return
        }
        var details = ["opened via \(route)"]
        let title = element("panelTitle").label
        if title.lowercased().replacingOccurrences(of: "&", with: "and") != panel.label.lowercased().replacingOccurrences(of: "&", with: "and") {
            details.append("title='\(title)' expected '\(panel.label)'")
        }
        // Content: the panel's own page (control.<id>.*) or its generic command list / empty state.
        let hasContent = exists(prefix: "control.\(panel.id)")
        details.append(hasContent ? "content present" : "NO control.\(panel.id).* content")
        var refusals: [String] = []
        var acted = 0
        for target in actionTargets(panel: panel.id) {
            guard target.exists, canTap(target) else { continue }
            let tid = target.identifier
            target.tap()
            acted += 1
            details.append("tap \(tid)")
            pause(0.8)
            let sheet = resolveSheet()
            if !sheet.text.isEmpty { details.append(sheet.text) }
            if let r = sheet.refused { refusals.append(r) }
            refusals += dismissStrays()
            if !alive(name) { return }
        }
        for r in refusals { note("\(name): \(r)") }
        if !refusals.isEmpty { details.append("MESSAGES=\(refusals.joined(separator: " || "))") }
        recover(undoLabelBefore: undoBefore)
        closePanelIfOpen()
        if !alive(name) { return }
        if !hasContent {
            record(name, reached: false, cause: "no-content", details.joined(separator: "; "))
        } else if !refusals.isEmpty {
            record(name, reached: false, cause: "engine-refused", details.joined(separator: "; "))
        } else {
            if acted == 0 { details.append("nothing tappable to act on (no buttons)") }
            record(name, reached: true, details.joined(separator: "; "))
        }
    }
}
