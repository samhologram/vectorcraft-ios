import Foundation

/// The inspector panels with a dedicated page. `rawValue` is the `panel_catalog()` id (the `panel` param of
/// `window.panel`). Every other catalog panel is shown by the UI's generic "commands of this panel" page.
enum Panel: String, CaseIterable, Identifiable, Sendable {
    case properties, layers, color, swatches, stroke, gradient, transparency, appearance, align, pathfinder,
         transform, artboards, character, paragraph, history, symbols, brushes, graphicStyles, docInfo, info, navigator

    var id: String { rawValue }

    /// Maps a `panel_catalog()` id (any case) onto a dedicated panel.
    static func from(panelID: String) -> Panel? {
        let key = panelID.trimmingCharacters(in: .whitespaces).lowercased()
        return allCases.first { $0.rawValue.lowercased() == key }
    }
}
