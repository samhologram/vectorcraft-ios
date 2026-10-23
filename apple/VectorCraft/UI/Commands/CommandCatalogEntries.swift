import SwiftUI
import VectorCraftKit

/// One command (engine or desktop UI-only) as the palette and the menus show it.
struct CatalogEntry: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let menu: [String]
    let shortcut: String?
    let doc: String
    let isQuery: Bool
    let isUI: Bool
}

/// Flat view of `command_catalog()` + `ui_command_catalog()` for the palette, the generic panel pages and the forms.
enum UICatalog {
    static let entries: [CatalogEntry] = {
        var out: [CatalogEntry] = []
        var seen = Set<String>()
        for c in commandCatalog() where seen.insert(c.id).inserted {
            out.append(CatalogEntry(id: c.id, label: c.label, menu: c.menu, shortcut: c.shortcut, doc: c.params, isQuery: c.isQuery, isUI: false))
        }
        for c in uiCommandCatalog() where seen.insert(c.id).inserted {
            out.append(CatalogEntry(id: c.id, label: c.label, menu: [], shortcut: c.shortcut, doc: c.params, isQuery: false, isUI: true))
        }
        return out
    }()

    static let byID: [String: CatalogEntry] = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    /// Commands the desktop menu bar places under a menu title, for the palette's grouping.
    static let menuTitles: [String] = ["File", "Edit", "Object", "Type", "Select", "Effect", "View", "Window", "Help"]

    /// Reason a command is unavailable on iOS (nil = supported).
    static func unsupported(_ id: String) -> String? { commandPlatformSupport(id: id) }
}
