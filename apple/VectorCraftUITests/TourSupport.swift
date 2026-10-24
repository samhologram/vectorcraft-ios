import XCTest
import UIKit

/// One visited item of a coverage tour.
struct TourItem {
    enum Outcome { case reached, notReached, skipped }
    let name: String
    let outcome: Outcome
    /// Cause class of a miss: off-screen, missing-identifier, engine-refused, no-effect, disabled, CRASH, ...
    let cause: String
    let detail: String
    var reached: Bool { outcome == .reached }
}

// MARK: - Navigation helpers shared by the smoke test and the tours

extension VectorCraftUITestCase {
    /// Closes an open menu or popover without acting on the canvas.
    func closeMenus() {
        let dismiss = app.otherElements["PopoverDismissRegion"]
        if dismiss.exists && dismiss.isHittable {
            dismiss.tap()
        } else {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).tap()
        }
        pause(0.5)
    }

    /// Opens the "..." overflow menu and walks `path` (["File"], ["File", "Export"]): each step is the identifier
    /// `menu.<Title>[.<Sub>…]`. Returns nil on success, otherwise the cause (the menu is left closed).
    func openOverflowPath(_ path: [String]) -> String? {
        guard let more = hit("menu.more") else {
            return element("menu.more").exists ? "off-screen: menu.more" : "missing-identifier: menu.more"
        }
        more.tap()
        pause(0.7)
        var id = "menu"
        for segment in path {
            id += "." + segment
            let target = element(id)
            guard target.waitForExistence(timeout: 3) else {
                closeMenus()
                return "missing-identifier: \(id)"
            }
            guard canTap(target) else {
                closeMenus()
                return "off-screen: \(id)"
            }
            target.tap()
            pause(0.5)
        }
        return nil
    }

    // MARK: Tools

    /// The scrolling container of the tool buttons: the iPad palette (vertical) or the iPhone strip (horizontal).
    private var toolContainer: (element: XCUIElement, vertical: Bool)? {
        let palette = element("toolPalette")
        if palette.exists { return (palette, true) }
        let strip = element("toolStrip")
        if strip.exists { return (strip, false) }
        return nil
    }

    /// The group button `toolGroup.<first>` scrolled into reach. Cause is "" on success.
    func revealToolGroup(_ group: String) -> (XCUIElement?, String) {
        let id = "toolGroup.\(group)"
        if let e = hit(id) { return (e, "") }
        guard element(id).exists else { return (nil, "missing-identifier") }
        guard let (container, vertical) = toolContainer else { return (nil, "off-screen") }
        let steps: [(Bool, Int)] = [(true, 12), (false, 30)]   // forward first, then all the way back
        for (forward, count) in steps {
            for _ in 0..<count {
                switch (vertical, forward) {
                case (true, true): container.swipeUp(velocity: .slow)
                case (true, false): container.swipeDown(velocity: .slow)
                case (false, true): container.swipeLeft(velocity: .slow)
                case (false, false): container.swipeRight(velocity: .slow)
                }
                pause(0.3)
                if let e = hit(id) { return (e, "") }
            }
        }
        return (nil, "off-screen")
    }

    /// Selects a tool through the real UI: the group button, then its flyout `tool.<id>` for multi-tool groups.
    /// Returns nil on success, otherwise the cause.
    func selectTool(_ tool: String, group: String, multi: Bool) -> String? {
        let (button, cause) = revealToolGroup(group)
        guard let button else { return cause }
        if !multi {
            button.tap()
            pause(0.6)
        } else {
            button.press(forDuration: 0.8)
            pause(0.6)
            var item = hit("tool.\(tool)")
            if item == nil {
                // iPad: a tap on the selected group opens its flyout as well.
                button.tap()
                pause(0.6)
                item = hit("tool.\(tool)")
            }
            guard let item else {
                closeMenus()
                return element("tool.\(tool)").exists ? "off-screen: flyout item" : "missing-identifier: tool.\(tool) (flyout did not open)"
            }
            item.tap()
            pause(0.6)
        }
        dismissStrays()
        if let b = revealToolGroup(group).0, !b.isSelected {
            return "tool-not-selected: toolGroup.\(group) lacks the selected trait after picking \(tool)"
        }
        return nil
    }

    // MARK: Panels

    /// Opens a panel through the real UI. Returns the route used ("switcher", "switcher-more", "window-menu",
    /// "window-menu-more") or nil with a note when it could not be reached; `cause` receives the class of the miss.
    func openPanel(_ panel: String, cause: inout String) -> String? {
        let id = "panel.\(panel)"
        var route: String?
        if let e = hit(id) {
            e.tap()
            route = "switcher"
        } else if usesToolPalette, let add = hit("control.panelMenu") {
            add.tap()
            pause(0.6)
            if let item = hit(id) {
                item.tap()
                route = "dock-add"
            } else {
                closeMenus()
            }
        } else if let more = hit("panel.more") {
            more.tap()
            pause(0.6)
            if let item = hit(id) { item.tap(); route = "switcher-more" } else { closeMenus() }
        }
        if route == nil {
            // The Window menu: on the toolbar (iPad) or inside the overflow menu (iPhone).
            var opened = false
            if let menu = hit("menu.panels") {
                menu.tap()
                pause(0.6)
                opened = true
            } else if openOverflowPath([]) == nil, let menu = hit("menu.panels") {
                menu.tap()
                pause(0.6)
                opened = true
            }
            if opened {
                if let item = hit("\(id).menu") {
                    item.tap()
                    route = "window-menu"
                } else if let more = hit("menu.panels.more") {
                    more.tap()
                    pause(0.5)
                    if let item = hit("\(id).menu") { item.tap(); route = "window-menu-more" }
                }
                if route == nil {
                    cause = element("\(id).menu").exists ? "off-screen" : "missing-identifier"
                    closeMenus()
                    return nil
                }
            } else {
                cause = element("menu.panels").exists ? "off-screen" : "missing-identifier"
                return nil
            }
        }
        let openedID = usesToolPalette ? "panelBody.\(panel)" : "panelTitle"
        if !element(openedID).waitForExistence(timeout: 5) {
            cause = "panel-did-not-open"
            return nil
        }
        lastOpenedPanelID = panel
        pause(0.8)
        return route
    }

    /// Closes the panel sheet (iPhone) / inspector content; harmless when nothing is open.
    func closePanelIfOpen() {
        if usesToolPalette, let panel = lastOpenedPanelID {
            if let actions = hit("panelActions.\(panel)") {
                actions.tap()
                pause(0.4)
                if let close = hit("panelClose.\(panel)") {
                    close.tap()
                    lastOpenedPanelID = nil
                    pause(0.5)
                } else { closeMenus() }
            }
            return
        }
        guard element("panelTitle").exists, let close = hit("panel.close") else { return }
        close.tap()
        lastOpenedPanelID = nil
        let deadline = Date().addingTimeInterval(4)
        while element("panelTitle").exists && Date() < deadline { pause(0.3) }
        pause(0.5)
    }
}

// MARK: - Tour base class

/// Shared driver of the coverage tours (tools, panels, commands). Every item is visited through the real UI;
/// only a crash fails a test. Everything else lands in the `-tour-summary` attachment, where a miss
/// ("NOT-REACHED") stays visible as a bug to fix, never as a pass.
///
/// Environment (pass as `TEST_RUNNER_<NAME>=...` to xcodebuild): `TOUR_LIMIT=n` visits only the first n items,
/// `TOUR_ONLY=a,b` only those ids (tool / panel / command ids without any prefix).
@MainActor
class TourTestCase: VectorCraftUITestCase {
    var items: [TourItem] = []
    var landscape = false
    var tourName = ""
    var summaryAttached = false
    var extraSummaryLines: [String] = []
    var crashItems: [String] = []
    var relaunches: [String] = []

    var limit: Int? { ProcessInfo.processInfo.environment["TOUR_LIMIT"].flatMap { Int($0) } }
    var only: Set<String>? {
        guard let v = ProcessInfo.processInfo.environment["TOUR_ONLY"], !v.isEmpty else { return nil }
        return Set(v.split(separator: ",").map { String($0) })
    }

    // MARK: Setup

    /// Launches the demo app in the given orientation, opens a new document and waits for `demoReady`.
    func startTour(name: String, landscape: Bool) {
        self.landscape = landscape
        tourName = name
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        launchDemo(dark: false)
        continueAfterFailure = true
        prefix = "\(isPad ? "ipad" : "iphone")-\(landscape ? "landscape" : "portrait")-\(name)"
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        pause(1)
        openNewDocument()
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        pause(1)
    }

    // MARK: Recording

    func record(_ name: String, _ outcome: TourItem.Outcome, cause: String = "", _ detail: String = "") {
        items.append(TourItem(name: name, outcome: outcome, cause: cause, detail: detail))
        let tag = outcome == .reached ? "REACHED" : (outcome == .skipped ? "SKIPPED" : "NOT-REACHED")
        let line = "\(tag) \(name) [\(cause)] \(detail)"
        NSLog("TOUR %@", line)
        // Best-effort mirror on the host: a crash can end the run before the summary attachment exists.
        let path = "/tmp/vctour-\(prefix).log"
        if let data = (line + "\n").data(using: .utf8) {
            if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(data); try? h.close() }
            else { FileManager.default.createFile(atPath: path, contents: data) }
        }
    }

    func record(_ name: String, reached: Bool, cause: String = "", _ detail: String = "") {
        record(name, reached ? .reached : .notReached, cause: cause, detail)
    }

    func attachSummary() {
        guard !summaryAttached else { return }
        summaryAttached = true
        let reached = items.filter(\.reached).count
        let skipped = items.filter { $0.outcome == .skipped }.count
        let missed = items.filter { $0.outcome == .notReached }
        var causes: [String: Int] = [:]
        for m in missed { causes[m.cause.split(separator: ":").first.map(String.init) ?? m.cause, default: 0] += 1 }
        var lines = ["\(prefix) tour summary",
                     "items: \(items.count)  reached+acted: \(reached)  not-reached: \(missed.count)  skipped: \(skipped)",
                     "not-reached by cause: " + (causes.isEmpty ? "none" : causes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")),
                     ""]
        if !crashItems.isEmpty { lines += ["CRASHES at: " + crashItems.joined(separator: ", "), ""] }
        if !relaunches.isEmpty { lines += ["RELAUNCHES: " + relaunches.joined(separator: ", "), ""] }
        lines += items.map { i in
            switch i.outcome {
            case .reached: return "REACHED      \(i.name)  \(i.detail)"
            case .skipped: return "SKIPPED      \(i.name)  [\(i.cause)] \(i.detail)"
            case .notReached: return "NOT-REACHED  \(i.name)  [\(i.cause)] \(i.detail)"
            }
        }
        if !extraSummaryLines.isEmpty { lines += ["", "extra:"] + extraSummaryLines }
        lines += ["", "notes:"] + (notes.isEmpty ? ["none"] : notes)
        let text = lines.joined(separator: "\n")
        try? text.write(toFile: "/tmp/vctour-\(prefix)-summary.txt", atomically: true, encoding: .utf8)
        let attachment = XCTAttachment(string: text)
        attachment.name = "\(prefix)-tour-summary"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Crash handling

    /// True while the app runs in the foreground. After a crash the item is recorded as CRASH, the test is failed
    /// (the tour goes on so later items are still covered) and the app is relaunched on a fresh demo document.
    func alive(_ item: String) -> Bool {
        if app.state == .runningForeground && app.windows.firstMatch.exists { return true }
        crashItems.append(item)
        record(item, .notReached, cause: "CRASH", "app state \(app.state.rawValue) after this item; relaunched")
        XCTFail("CRASH (app not running in the foreground) at \(item)")
        relaunch(reason: "after crash at \(item)")
        return false
    }

    /// Fresh launch on a new demo document (after a crash, or to reset accumulated state).
    func relaunch(reason: String) {
        relaunches.append(reason)
        let saved = prefix
        app.terminate()
        launchDemo(dark: false)
        continueAfterFailure = true
        prefix = saved
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        pause(1)
        openNewDocument()
    }

    /// Back to a valid document after an item: strays dismissed, panels closed, undo to the label seen before.
    func recover(undoLabelBefore: String) {
        dismissStrays()
        if !element("canvas").exists { note("recover: canvas missing after item") }
        undo(toLabel: undoLabelBefore)
        dismissStrays()
    }
}

extension VectorCraftUITestCase {
    /// If a parameter sheet is open: fill defaults, confirm, record the engine's message (error or query result),
    /// close it. Returns a description ("" when no sheet) and a refusal message when the engine refused.
    func resolveSheet() -> (text: String, refused: String?) {
        let cancel = element("commandSheet.cancel")
        guard cancel.waitForExistence(timeout: 1.5) else { return ("", nil) }
        // The run button is `command.<id>.run`.
        let runQuery = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'command.' AND identifier ENDSWITH '.run'"))
        let run = runQuery.firstMatch
        var text = "sheet"
        if run.exists && !run.isEnabled {
            // Required fields without defaults: type a plain value into empty text fields.
            for field in app.textFields.allElementsBoundByIndex where field.exists && field.isHittable {
                let value = (field.value as? String) ?? ""
                if value.isEmpty || value == field.placeholderValue {
                    field.tap()
                    field.typeText("Tour")
                    text += " filled-text"
                }
            }
            if app.keyboards.count > 0 {
                let done = app.keyboards.buttons["return"].firstMatch
                if done.exists { done.tap() } else { app.keyboards.buttons["Return"].firstMatch.tap() }
            }
            pause(0.4)
        }
        var refused: String?
        if run.exists && run.isEnabled && run.isHittable {
            run.tap()
            text += " run"
            pause(1.2)
            let err = element("commandSheet.error")
            if err.exists { refused = err.label; text += " ERROR" }
            let result = element("commandSheet.result")
            if result.exists { text += " result=\(String(result.label.prefix(100)).replacingOccurrences(of: "\n", with: " "))" }
        } else if run.exists {
            text += " run-disabled"
            refused = "parameter sheet Run stays disabled with defaults"
        }
        let c = element("commandSheet.cancel")
        if c.exists, canTap(c) { c.tap() }
        pause(0.6)
        return (text, refused)
    }
}
