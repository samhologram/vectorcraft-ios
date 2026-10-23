import XCTest

/// Runs every command of the desktop menu layout (`TourCatalog.menuCommands`, generated) through the "..." overflow
/// menu: `menu.more` -> `menu.<Title>` [-> `menu.<Title>.<Sub>`] -> `command.<id>`. Command sheets are confirmed with
/// defaults, alerts and engine messages are recorded in full, state is restored by undo. Ids in
/// `ios-excluded-commands.txt` (reason in the summary) and the ones the iOS menus hand to the system are skipped
/// and listed as SKIPPED. Only a crash fails; misses are in the `-tour-summary` attachment.
@MainActor
final class CommandTourUITests: TourTestCase {
    func testCommandsPortrait() throws { try tour(landscape: false) }
    func testCommandsLandscape() throws { try tour(landscape: true) }

    /// A fresh document every this many acted items, so accumulated state cannot wedge the rest of the tour.
    private static let relaunchEvery = 60

    private func tour(landscape: Bool) throws {
        startTour(name: "commands", landscape: landscape)
        defer { attachSummary(); flushNotes() }
        XCTAssertFalse(TourCatalog.menuCommands.isEmpty, "TourCatalog.menuCommands is empty: regenerate it (run-ui-tests.sh --regen-lists)")
        var commands = TourCatalog.menuCommands
        if let only { commands = commands.filter { only.contains($0.id) } }
        extraSummaryLines.append("menu entries in the desktop layout: \(TourCatalog.menuCommands.count); toured: \(commands.count)")
        var deferred: [TourCatalog.MenuCommand] = []
        var acted = 0
        for cmd in commands {
            if let limit, items.count >= limit { break }
            if let reason = TourCatalog.excluded[cmd.id] {
                record(name(cmd), .skipped, cause: "ios-excluded", reason)
                continue
            }
            if TourCatalog.systemHandled.contains(cmd.id) {
                record(name(cmd), .skipped, cause: "system-handled", "not in the iOS menus by design (undo/redo/copy/paste/save/new/open/close/quit/preferences...)")
                continue
            }
            if acted > 0 && acted % Self.relaunchEvery == 0 { relaunch(reason: "periodic reset before \(cmd.id)") }
            acted += 1
            if !visit(cmd, final: false) { deferred.append(cmd) }
        }
        // Second chance for entries that were disabled: earlier commands may have changed the state.
        for cmd in deferred { _ = visit(cmd, final: true) }
    }

    private func name(_ cmd: TourCatalog.MenuCommand) -> String {
        "command.\(cmd.id)" + (cmd.paramsJson == "{}" ? "" : " \(cmd.paramsJson)") + "  [\(cmd.path.joined(separator: " > "))]"
    }

    /// The command's element inside the open menu: `command.<id>` or the repeated-entry form `command.<id>@<n>`.
    private func menuElement(_ cmd: TourCatalog.MenuCommand) -> (XCUIElement?, exists: Bool) {
        let ids = ["command.\(cmd.id)"] + (cmd.occurrence > 0 ? ["command.\(cmd.id)@\(cmd.occurrence)"] : [])
        for id in ids { if let e = hit(id) { return (e, true) } }
        let any = prefixQuery("command.\(cmd.id)@").firstMatch
        if any.exists, canTap(any) { return (any, true) }
        let present = ids.contains { element($0).exists } || any.exists
        return (nil, present)
    }

    /// Returns false when the entry was disabled and may be retried later.
    private func visit(_ cmd: TourCatalog.MenuCommand, final: Bool) -> Bool {
        let label = name(cmd)
        dismissStrays()
        closePanelIfOpen()
        if !element("canvas").exists {
            note("\(label): canvas missing before the item; relaunching")
            relaunch(reason: "no canvas before \(cmd.id)")
        }
        let undoBefore = undoLabel
        if let cause = openOverflowPath(cmd.path) {
            record(label, .notReached, cause: cause.split(separator: ":").first.map(String.init) ?? cause, cause)
            _ = alive(label)
            return true
        }
        let (target, present) = menuElement(cmd)
        guard let target else {
            closeMenus()
            let cause = present ? "off-screen" : "missing-identifier"
            record(label, .notReached, cause: cause,
                   present ? "command element exists in the menu but cannot be tapped" : "no command.\(cmd.id) in \(cmd.path.joined(separator: " > ")) (filtered for iOS or missing)")
            _ = alive(label)
            return true
        }
        if !target.isEnabled {
            let l = target.label.replacingOccurrences(of: "\n", with: " ")
            closeMenus()
            if !final { return false }
            record(label, .notReached, cause: "disabled", "still disabled after the tour: '\(l)'")
            _ = alive(label)
            return true
        }
        target.tap()
        pause(1.2)
        var parts: [String] = []
        let sheet = resolveSheet()
        if !sheet.text.isEmpty { parts.append(sheet.text) }
        var messages: [String] = []
        if let r = sheet.refused { messages.append(r) }
        // Palette / export / alerts the command opened.
        messages += dismissStrays()
        let changed = undoLabel != undoBefore
        parts.append("history changed=\(changed)")
        guard alive(label) else { return true }
        recover(undoLabelBefore: undoBefore)
        if messages.isEmpty {
            record(label, .reached, "\(parts.joined(separator: "; "))")
        } else {
            note("\(label): \(messages.joined(separator: " || "))")
            record(label, .notReached, cause: "engine-refused", "MESSAGE=" + messages.joined(separator: " || ") + "; " + parts.joined(separator: "; "))
        }
        return true
    }
}
