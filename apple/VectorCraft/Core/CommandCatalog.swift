import SwiftUI
@preconcurrency import VectorCraftKit

/// The data-driven command system. Wraps the engine catalog (`commandCatalog()`), the desktop UI-only commands
/// (`uiCommandCatalog()`), the desktop menu layout (`desktopMenuLayout()`), the tools and the panels. Menus, the
/// palette and parameter sheets are generated from it, so new engine commands appear without Swift changes.
@MainActor
final class CommandCatalog {
    static let shared = CommandCatalog()

    let commands: [CommandInfo]
    let uiCommands: [UiCommandInfo]
    /// Desktop menu bar order: File, Edit, Object, Type, Select, Effect, View, Window, Help.
    let menus: [MenuSection]
    let toolGroups: [ToolGroupInfo]
    let panels: [PanelInfo]

    private let engineByID: [String: CommandInfo]
    private let uiByID: [String: UiCommandInfo]
    private let toolByID: [String: ToolInfo]
    private var paramCache: [String: [ParamField]] = [:]
    private var supportCache: [String: String?] = [:]

    private init() {
        AppEnvironment.bootstrap()
        let engine = commandCatalog()
        let ui = uiCommandCatalog()
        commands = engine
        uiCommands = ui
        menus = desktopMenuLayout()
        toolGroups = toolCatalog()
        panels = panelCatalog()
        engineByID = Dictionary(engine.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        uiByID = Dictionary(ui.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        toolByID = Dictionary(toolCatalog().flatMap(\.tools).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Lookups

    func command(_ id: String) -> CommandInfo? { engineByID[id] }
    func uiCommand(_ id: String) -> UiCommandInfo? { uiByID[id] }
    func tool(_ id: String) -> ToolInfo? { toolByID[id] }
    func isUI(_ id: String) -> Bool { engineByID[id] == nil && uiByID[id] != nil }
    func isKnown(_ id: String) -> Bool { engineByID[id] != nil || uiByID[id] != nil }

    func label(_ id: String) -> String { engineByID[id]?.label ?? uiByID[id]?.label ?? id }

    /// Queries do not journal (no undo step).
    func isQuery(_ id: String) -> Bool { engineByID[id]?.isQuery ?? false }

    func shortcutText(_ id: String) -> String? {
        let text = engineByID[id]?.shortcut ?? uiByID[id]?.shortcut
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    func shortcut(_ id: String) -> KeyboardShortcut? {
        shortcutText(id).flatMap(Self.parseShortcut)
    }

    func params(_ id: String) -> [ParamField] {
        if let cached = paramCache[id] { return cached }
        let fields = commandParams(id: id)
        paramCache[id] = fields
        return fields
    }

    /// Alias of `params(_:)`.
    func params(for id: String) -> [ParamField] { params(id) }

    /// Any field that must be given (free-form fragments, `key == ""`, do not count).
    func needsParams(_ id: String) -> Bool {
        params(id).contains { !$0.key.isEmpty && !$0.isOptional }
    }

    /// True when running the command from a menu should ask for parameters first: it needs some, or its label
    /// ends in an ellipsis and it has at least one field to show.
    func needsSheet(_ id: String) -> Bool {
        guard let info = engineByID[id] else { return false }
        let fields = params(id).filter { !$0.key.isEmpty }
        if fields.contains(where: { !$0.isOptional }) { return true }
        return (info.label.hasSuffix("\u{2026}") || info.label.hasSuffix("...")) && !fields.isEmpty
    }

    /// False for commands that make no sense on iOS (`ios-excluded-commands.txt`).
    func isAvailable(_ id: String) -> Bool {
        if let cached = supportCache[id] { return cached == nil }
        let reason = commandPlatformSupport(id: id)
        supportCache[id] = .some(reason)
        return reason == nil
    }

    /// Engine commands whose menu path is exactly `path`, in catalog order.
    func commandIDs(menuPath path: [String]) -> [String] {
        commands.filter { $0.menu == path }.map(\.id)
    }

    func panelInfo(_ id: String) -> PanelInfo? { panels.first { $0.id == id } }

    // MARK: Shortcut parsing

    /// Parses egui notation: "Cmd+Shift+R", "Shift+G", "E", "=", "Escape". Returns nil for function keys and
    /// anything SwiftUI cannot express.
    nonisolated static func parseShortcut(_ text: String) -> KeyboardShortcut? {
        // "Cmd++" ends in a literal "+": split on the last separator only when a key follows it.
        var parts = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        if parts.last == "", parts.count >= 2 {
            parts.removeLast()
            parts[parts.count - 1] = "+"
        }
        guard let keyName = parts.last, !keyName.isEmpty else { return nil }
        var modifiers: EventModifiers = []
        for part in parts.dropLast() {
            switch part.lowercased() {
            case "cmd", "command", "meta": modifiers.insert(.command)
            case "ctrl", "control": modifiers.insert(.control)
            case "alt", "option", "opt": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            default: return nil
            }
        }
        let key: KeyEquivalent
        switch keyName.lowercased() {
        case "backspace": key = .delete
        case "delete": key = .deleteForward
        case "enter", "return": key = .return
        case "tab": key = .tab
        case "space": key = .space
        case "esc", "escape": key = .escape
        case "up": key = .upArrow
        case "down": key = .downArrow
        case "left": key = .leftArrow
        case "right": key = .rightArrow
        default:
            guard keyName.count == 1, let ch = keyName.lowercased().first else { return nil }
            key = KeyEquivalent(ch)
        }
        return KeyboardShortcut(key, modifiers: modifiers)
    }

    /// "Cmd+Shift+R" -> a symbol string for the palette.
    nonisolated static func display(_ text: String) -> String {
        text.split(separator: "+", omittingEmptySubsequences: false).map { part -> String in
            switch part.lowercased() {
            case "cmd": "\u{2318}"
            case "shift": "\u{21E7}"
            case "alt": "\u{2325}"
            case "ctrl": "\u{2303}"
            case "backspace": "\u{232B}"
            case "delete": "\u{2326}"
            case "enter": "\u{21A9}"
            case "escape": "\u{238B}"
            default: String(part).uppercased()
            }
        }.joined()
    }
}
