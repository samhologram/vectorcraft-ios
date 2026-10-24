import XCTest
import UIKit

/// Shared driver of the UI tests. Launches with `-VectorCraftDemo -VectorCraftResetSettings`, gets past the document
/// browser by creating a new document, waits for the `demoReady` marker, and records every missing element as a
/// note (a `-notes` attachment) instead of failing. Only a missing window, a missing document or a crash fails a
/// test. No screenshots are attached (project rule): notes and tour summaries carry the evidence.
/// Drives only the accessibility identifiers of apple/docs/CONTRACT.md §5.
@MainActor
class VectorCraftUITestCase: XCTestCase {
    var app: XCUIApplication!
    var notes: [String] = []
    var prefix = ""
    var lastOpenedPanelID: String?
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // MARK: Launch

    /// Launches the demo app. `dark` picks the system appearance.
    func launchDemo(dark: Bool, extraArguments: [String] = []) {
        continueAfterFailure = false
        let mode = dark ? "dark" : "light"
        prefix = "\(isPad ? "ipad" : "iphone")-\(mode)"
        notes = []
        XCUIDevice.shared.appearance = dark ? .dark : .light
        app = XCUIApplication()
        app.launchArguments = ["-VectorCraftDemo", "-VectorCraftResetSettings", "-AppleLanguages", "(en)",
                               "-AppleLocale", "en_US"] + extraArguments
        app.launchEnvironment["VECTORCRAFT_UITEST"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "The app did not launch")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 60), "The app has no window")
    }

    /// Past the document browser / launch scene: creates a new document and waits for `demoReady`.
    /// Fails (the test cannot continue) only when no document opens.
    func openNewDocument() {
        pause(2)
        if !hasForegroundCanvas {
            chooseLocalDocumentLocationIfNeeded()
            if !tapCreateDocument() { note("start: no create-document control found in the browser") }
        }
        // A name prompt or template chooser may follow: accept the default.
        for label in ["Create", "Done", "Save"] {
            let b = app.alerts.buttons[label].firstMatch
            if b.waitForExistence(timeout: 1) { b.tap(); break }
        }
        let alert = app.alerts.firstMatch
        if alert.exists {
            let message = ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " | ")
            XCTFail("Document creation alert: \(message)")
            return
        }
        let opened = element("canvas").waitForExistence(timeout: 90)
        XCTAssertTrue(opened, "No document opened: the canvas never appeared (see \(prefix)-notes)")
        // DocumentGroup can briefly expose an editor behind its system Recents browser. A canvas that merely
        // exists in the accessibility tree is not an open, usable document. Dismiss the browser only when an
        // editor has appeared behind it, then require a foreground canvas before any story uses the controls.
        let browser = prefixQuery("DOC.browsingRoot").firstMatch
        if browser.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
            pause(0.5)
        }
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if hasForegroundCanvas { break }
            pause(0.5)
        }
        XCTAssertFalse(browser.exists, "The system document browser still covers the editor")
        XCTAssertTrue(hasForegroundCanvas, "No foreground, reachable canvas opened")
        if !element("demoReady").waitForExistence(timeout: 60) { note("start: demoReady marker never appeared") }
        pause(1)
    }

    /// NewDocumentButton creates in the directory selected by DocumentGroup's browser. A fresh simulator often
    /// starts in Recents, which is a collection rather than a writable directory. Choose local storage when the
    /// system browser exposes it; keep the browser visible for diagnosis if that route is unavailable.
    func chooseLocalDocumentLocationIfNeeded() {
        let browser = prefixQuery("DOC.browsingRoot").firstMatch
        guard browser.exists else { return }
        let browse = app.buttons.matching(NSPredicate(format: "label == %@", "Browse"))
        if let button = browse.allElementsBoundByIndex.first(where: canTap) {
            button.tap()
            pause(0.5)
        }
        let localLabel = isPad ? "On My iPad" : "On My iPhone"
        let local = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", localLabel))
        if let location = local.allElementsBoundByIndex.first(where: canTap) {
            location.tap()
            pause(0.5)
        } else {
            note("start: system browser has no reachable \(localLabel) location")
        }
    }

    /// Taps whatever the system shows to create a document: the launch scene's "New Drawing", the browser's
    /// "Create Document" or its "+" / "Add" button. Returns whether something was tapped.
    @discardableResult
    func tapCreateDocument() -> Bool {
        let predicates = ["New Drawing", "Create Document", "Create", "New Document", "Add", "+"]
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if hasForegroundCanvas { return true }
            for label in predicates {
                let q = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label))
                for b in q.allElementsBoundByIndex where b.exists && b.isHittable {
                    b.tap()
                    return true
                }
            }
            // The launch scene exposes its button as a static cell on some systems.
            let cell = app.cells.matching(NSPredicate(format: "label CONTAINS[c] 'New' OR label CONTAINS[c] 'Create'")).firstMatch
            if cell.exists && cell.isHittable { cell.tap(); return true }
            pause(1)
        }
        return false
    }

    // MARK: Lookup

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// A document is ready only when its canvas is actionable and the system file browser has gone away.
    var hasForegroundCanvas: Bool {
        !prefixQuery("DOC.browsingRoot").firstMatch.exists && hit("canvas") != nil
    }

    /// On screen and tappable. The frame is checked first: `isHittable` fails the test for elements far off screen.
    func canTap(_ e: XCUIElement) -> Bool {
        guard e.exists else { return false }
        let f = e.frame
        let w = app.windows.firstMatch.frame
        guard !f.isEmpty, w.contains(CGPoint(x: f.midX, y: f.midY)) else { return false }
        return e.isHittable
    }

    /// The first element with `identifier` that can be tapped.
    func hit(_ identifier: String) -> XCUIElement? {
        let q = app.descendants(matching: .any).matching(identifier: identifier)
        for e in q.allElementsBoundByIndex where canTap(e) { return e }
        return nil
    }

    func prefixQuery(_ prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    func hit(prefix: String) -> XCUIElement? {
        for e in prefixQuery(prefix).allElementsBoundByIndex where canTap(e) { return e }
        return nil
    }

    func exists(prefix: String) -> Bool { prefixQuery(prefix).firstMatch.exists }

    /// Waits until any of the identifiers exists; returns the first found (nil on timeout).
    func waitForAny(_ identifiers: [String], timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for id in identifiers where element(id).exists { return id }
            pause(0.5)
        }
        return nil
    }

    /// Taps the element with `identifier` if it can be reached; records a note otherwise.
    @discardableResult
    func tap(_ identifier: String, timeout: TimeInterval = 5) -> Bool {
        let e = element(identifier)
        guard e.waitForExistence(timeout: timeout) else { note("\(identifier): not found"); return false }
        guard let visible = hit(identifier) else {
            note("\(identifier): exists but no matching element is hittable (off screen or covered)")
            return false
        }
        visible.tap()
        return true
    }

    /// Layout idiom actually on screen (a narrow iPad window uses the phone layout).
    var usesToolPalette: Bool { element("toolPalette").exists }

    // MARK: Alerts and strays

    /// The full message of an alert on screen, dismissed; nil when none.
    func dismissAlert() -> String? {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: 1) else { return nil }
        let text = ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " | ")
        let ok = element("errorAlert.ok")
        if ok.exists && ok.isHittable { ok.tap() } else if alert.buttons.firstMatch.exists { alert.buttons.firstMatch.tap() }
        return text
    }

    /// Dismisses what the last action left open (alert, command sheet, palette, export, popovers, menus) and returns
    /// the full text of every alert met on the way.
    @discardableResult
    func dismissStrays() -> [String] {
        var alerts: [String] = []
        for _ in 0..<6 {
            if app.alerts.firstMatch.exists, let text = dismissAlert() {
                alerts.append(text)
                pause(0.6)
                continue
            }
            var acted = false
            for id in ["commandSheet.cancel", "palette.done"] where element(id).exists {
                if let c = hit(id) { c.tap(); pause(0.8); acted = true; break }
            }
            if acted { continue }
            if element("export.done").exists, let c = hit("export.done") { c.tap(); pause(0.8); continue }
            // An open menu / popover: tapping the dismiss region closes it.
            let dismiss = app.otherElements["PopoverDismissRegion"]
            if dismiss.exists && dismiss.isHittable { dismiss.tap(); pause(0.6); continue }
            if app.sheets.firstMatch.exists || app.popovers.firstMatch.exists {
                var closed = false
                for title in ["Cancel", "Done", "Close"] {
                    let host = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.popovers.firstMatch
                    let b = host.buttons[title].firstMatch
                    if b.exists && b.isHittable { b.tap(); pause(0.8); closed = true; break }
                }
                if closed { continue }
            }
            break
        }
        return alerts
    }

    func pause(_ seconds: TimeInterval) {
        let e = expectation(description: "pause")
        e.isInverted = true
        wait(for: [e], timeout: seconds)
    }

    // MARK: Canvas gestures

    func canvasDrag(from a: (CGFloat, CGFloat), to b: (CGFloat, CGFloat), hold: TimeInterval = 0.15) {
        let canvas = element("canvas")
        guard canvas.exists else { note("canvasDrag: no canvas"); return }
        let from = canvas.coordinate(withNormalizedOffset: CGVector(dx: a.0, dy: a.1))
        let to = canvas.coordinate(withNormalizedOffset: CGVector(dx: b.0, dy: b.1))
        from.press(forDuration: hold, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        pause(0.5)
    }

    func canvasTap(_ p: (CGFloat, CGFloat)) {
        let canvas = element("canvas")
        guard canvas.exists else { note("canvasTap: no canvas"); return }
        canvas.coordinate(withNormalizedOffset: CGVector(dx: p.0, dy: p.1)).tap()
        pause(0.4)
    }

    // MARK: Undo / redo (toolbar buttons `undo`, `redo`)

    var undoElement: XCUIElement { element("undo") }
    var canUndo: Bool { let u = undoElement; return u.exists && u.isEnabled }
    var canRedo: Bool { let r = element("redo"); return r.exists && r.isEnabled }
    /// The undo button's label ("Undo <step>"): changes when the history changes.
    var undoLabel: String { undoElement.exists ? undoElement.label : "" }

    @discardableResult
    func tapUndo() -> Bool {
        guard canUndo, canTap(undoElement) else { return false }
        undoElement.tap()
        pause(0.6)
        return true
    }

    @discardableResult
    func tapRedo() -> Bool {
        let r = element("redo")
        guard canRedo, canTap(r) else { return false }
        r.tap()
        pause(0.6)
        return true
    }

    /// Undoes until the undo label is `label` again (or nothing is left / `count` steps were taken).
    func undo(toLabel label: String, max count: Int = 8) {
        for _ in 0..<count {
            if undoLabel == label { return }
            guard tapUndo() else { return }
        }
    }

    // MARK: Notes

    func note(_ text: String) {
        notes.append(text)
        NSLog("VectorCraftUITests note: %@", text)
    }

    func flushNotes(_ name: String = "notes") {
        let attachment = XCTAttachment(string: notes.isEmpty ? "no notes" : notes.joined(separator: "\n"))
        attachment.name = "\(prefix)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
