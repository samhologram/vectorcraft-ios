import SwiftUI
@preconcurrency import VectorCraftKit

// iPadOS menu bar, generated from the desktop menu layout (`CommandCatalog.menus`): File, Edit, Object, Type,
// Select, Effect, View, Window, Help. File / Edit / View / Window / Help extend the system menus (custom menus
// appear after View); Object, Type, Select and Effect are custom. Every item acts on the focused scene's model
// (`@FocusedValue(\.documentModel)`) and carries `command.<id>` as accessibility identifier.

// MARK: - Menu tree

/// One entry of a generated menu (a node of `MenuItemInfo`, pre-filtered for this platform).
struct MenuNode: Identifiable {
    enum Kind {
        case command(id: String, params: [String: Any], accessibilityID: String)
        case separator
        case submenu(label: String, children: [MenuNode])
    }

    let id: Int
    let label: String
    let kind: Kind
}

@MainActor
enum MenuLayout {
    /// Handled by the system groups or by the canvas' responder actions (copy, cut, paste, select all).
    private static let hidden: Set<String> = [
        "file.newDialog", "file.newWithoutDialog", "file.newFromTemplate", "file.open", "file.clearRecent",
        "file.recentFiles", "file.close", "file.closeAll", "file.save", "file.saveAs", "app.quit", "app.home",
        "edit.undo", "edit.redo", "edit.cut", "edit.copy", "edit.paste", "edit.preferences", "edit.keyboardShortcuts",
    ]
    /// Shortcuts the system or the canvas already uses.
    private static let reserved: Set<String> = [
        "cmd+n", "cmd+o", "cmd+w", "cmd+q", "cmd+h", "cmd+m", "cmd+p", "cmd+s", "cmd+c", "cmd+x", "cmd+v", "cmd+a",
        "cmd+z", "cmd+shift+z", "cmd+,", "cmd+f", "cmd+k",
        // UIKit supplies Paste and Match Style. Reusing it for Paste on All Artboards aborts the menu builder.
        "cmd+alt+shift+v",
    ]

    private static var cache: [String: [MenuNode]] = [:]
    private static var seenAccessibilityIDs: [String: Int] = [:]
    private static var shortcutOwner: [String: KeyboardShortcut] = [:]
    private static var takenShortcuts: Set<String> = reserved

    private static var built = false

    /// Builds every section once, in desktop order, so shortcut conflicts resolve the same way every run.
    private static func buildAll() {
        guard !built else { return }
        built = true
        for section in CommandCatalog.shared.menus {
            var counter = 0
            cache[section.title] = build(section.items, counter: &counter)
        }
    }

    private static func isHidden(_ id: String) -> Bool {
        hidden.contains(id) || id.hasPrefix("file.openRecent")
    }

    private static func isVisible(_ id: String) -> Bool {
        let catalog = CommandCatalog.shared
        guard catalog.isKnown(id), !isHidden(id) else { return false }
        return catalog.isUI(id) ? DocumentModel.implementsUI(id) : catalog.isAvailable(id)
    }

    /// The top-level section titles, in desktop order, that have entries.
    static var titles: [String] { CommandCatalog.shared.menus.map(\.title) }

    /// Entries of the top-level menu `title`.
    static func nodes(for title: String) -> [MenuNode] {
        buildAll()
        return cache[title] ?? []
    }

    private static func build(_ items: [MenuItemInfo], counter: inout Int) -> [MenuNode] {
        var out: [MenuNode] = []
        for item in items {
            switch item.kind {
            case "separator":
                if let last = out.last, case .separator = last.kind { continue }
                if out.isEmpty { continue }
                counter += 1
                out.append(MenuNode(id: counter, label: "", kind: .separator))
            case "submenu":
                let children = build(item.children, counter: &counter)
                guard !children.isEmpty else { continue }
                counter += 1
                out.append(MenuNode(id: counter, label: item.label, kind: .submenu(label: item.label, children: children)))
            case "command":
                guard isVisible(item.command) else { continue }
                let params = MenuLayout.parse(item.paramsJson)
                let n = seenAccessibilityIDs[item.command, default: 0]
                seenAccessibilityIDs[item.command] = n + 1
                let ax = n == 0 ? "command.\(item.command)" : "command.\(item.command)@\(n)"
                if params.isEmpty { claimShortcut(item.command) }
                counter += 1
                out.append(MenuNode(id: counter, label: item.label, kind: .command(id: item.command, params: params, accessibilityID: ax)))
            default:
                continue  // "todo": not implemented on desktop either
            }
        }
        while let last = out.last, case .separator = last.kind { out.removeLast() }
        return out
    }

    private static func parse(_ json: String) -> [String: Any] {
        DocumentModel.decodeObject(json) ?? [:]
    }

    /// The first command to ask for a combination gets it. Combinations the system owns, and shortcuts without
    /// Command / Control / Option (tool keys live on the editor's hidden buttons), are never taken.
    private static func claimShortcut(_ id: String) {
        guard shortcutOwner[id] == nil, let shortcut = CommandCatalog.shared.shortcut(id) else { return }
        guard !shortcut.modifiers.isDisjoint(with: [.command, .control, .option]) else { return }
        let key = name(of: shortcut)
        guard !takenShortcuts.contains(key) else { return }
        takenShortcuts.insert(key)
        shortcutOwner[id] = shortcut
    }

    static func shortcut(for id: String) -> KeyboardShortcut? { shortcutOwner[id] }

    private static func name(of s: KeyboardShortcut) -> String {
        var text = ""
        if s.modifiers.contains(.command) { text += "cmd+" }
        if s.modifiers.contains(.control) { text += "ctrl+" }
        if s.modifiers.contains(.option) { text += "alt+" }
        if s.modifiers.contains(.shift) { text += "shift+" }
        return text + String(s.key.character)
    }
}

// MARK: - Menu views

/// One catalog command as a menu button.
struct CommandMenuItem: View {
    let model: DocumentModel?
    let label: String
    let id: String
    let params: [String: Any]
    let accessibilityID: String

    var body: some View {
        let button = Button(label) { model?.present(id, params: params) }
            .disabled(!(model?.isEnabled(id) ?? false))
            .accessibilityIdentifier(accessibilityID)
        if params.isEmpty, let shortcut = MenuLayout.shortcut(for: id) {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }
}

/// The nodes of one generated menu (the content of a `CommandGroup` / `CommandMenu`, or a submenu).
struct MenuEntries: View {
    let model: DocumentModel?
    let nodes: [MenuNode]

    var body: some View {
        ForEach(nodes) { node in
            switch node.kind {
            case .command(let id, let params, let ax):
                CommandMenuItem(model: model, label: node.label, id: id, params: params, accessibilityID: ax)
            case .separator:
                Divider()
            case .submenu(let label, let children):
                Menu(label) { MenuEntries(model: model, nodes: children) }
            }
        }
    }
}

/// A whole top-level section by title.
private struct GeneratedMenu: View {
    let model: DocumentModel?
    let title: String

    var body: some View {
        // Reading the revision makes the enabled states follow the document.
        let _ = model?.state.revision
        MenuEntries(model: model, nodes: MenuLayout.nodes(for: title))
    }
}

// MARK: - Commands

struct EditorCommands: Commands {
    @FocusedValue(\.documentModel) private var model

    private var undoTitle: String {
        guard let label = model?.state.undoLabel, !label.isEmpty else { return String(localized: "Undo") }
        return String(localized: "Undo") + " " + label
    }

    private var redoTitle: String {
        guard let label = model?.state.redoLabel, !label.isEmpty else { return String(localized: "Redo") }
        return String(localized: "Redo") + " " + label
    }

    // A commands builder takes at most 10 items, so the body is split in groups.
    var body: some Commands {
        fileCommands
        editCommands
        objectMenus
        viewCommands
        windowAndHelpCommands
    }

    @CommandsBuilder private var fileCommands: some Commands {
        CommandGroup(after: .newItem) {
            GeneratedMenu(model: model, title: "File")
        }
    }

    @CommandsBuilder private var editCommands: some Commands {
        // edit.undo / edit.redo replace the system group; they go through the engine history (UndoManager mirror).
        CommandGroup(replacing: .undoRedo) {
            Button(undoTitle) { model?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!(model?.state.canUndo ?? false))
                .accessibilityIdentifier("command.edit.undo")
            Button(redoTitle) { model?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(model?.state.canRedo ?? false))
                .accessibilityIdentifier("command.edit.redo")
        }
        // Cut / copy / paste / select all stay the system's: the canvas implements them as responder actions.
        CommandGroup(after: .pasteboard) {
            GeneratedMenu(model: model, title: "Edit")
        }
    }

    @CommandsBuilder private var objectMenus: some Commands {
        CommandMenu("Object") { GeneratedMenu(model: model, title: "Object") }
        CommandMenu("Type") { GeneratedMenu(model: model, title: "Type") }
        CommandMenu("Select") { GeneratedMenu(model: model, title: "Select") }
        CommandMenu("Effect") { GeneratedMenu(model: model, title: "Effect") }
    }

    @CommandsBuilder private var viewCommands: some Commands {
        CommandGroup(after: .toolbar) {
            Button(model?.isFullscreen == true ? "Exit Full Screen Canvas" : "Full Screen Canvas") {
                model?.toggleFullscreen()
            }
            .keyboardShortcut("f", modifiers: [.control, .command])
            .disabled(model == nil)
            GeneratedMenu(model: model, title: "View")
        }
    }

    @CommandsBuilder private var windowAndHelpCommands: some Commands {
        CommandGroup(after: .windowArrangement) {
            GeneratedMenu(model: model, title: "Window")
        }
        CommandGroup(after: .help) {
            GeneratedMenu(model: model, title: "Help")
        }
    }
}
