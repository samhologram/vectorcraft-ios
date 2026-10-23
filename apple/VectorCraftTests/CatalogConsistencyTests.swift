import Foundation
import Testing
@preconcurrency import VectorCraftKit
@testable import VectorCraft

/// The Swift side of the catalogs: `CommandCatalog` wraps the bridge catalogs (CONTRACT §4) and the menus must be
/// built from the desktop layout.
@MainActor
struct CatalogConsistencyTests {
    @Test func commandCatalogWrapsTheBridge() {
        let catalog = CommandCatalog.shared
        #expect(!catalog.menus.isEmpty)
        #expect(!catalog.toolGroups.isEmpty)
        #expect(!catalog.panels.isEmpty)
        #expect(catalog.isKnown("shape.rectangle"))
        #expect(!catalog.isKnown("no.such.command"))
        #expect(!catalog.label("shape.rectangle").isEmpty)
    }

    @Test func everyPanelEnumCaseIsInThePanelCatalog() {
        let ids = Set(panelCatalog().map(\.id))
        for panel in Panel.allCases where !ids.contains(panel.rawValue) {
            Issue.record("Panel.\(panel.rawValue) is not a panel_catalog() id")
        }
    }

    @Test func everyToolHasASymbol() {
        for tool in toolCatalog().flatMap(\.tools) {
            #expect(!CommandCatalog.shared.symbol(forTool: tool.id).isEmpty, "tool \(tool.id)")
        }
    }

    @Test func menuLayoutTitlesFollowTheDesktopOrder() {
        let titles = MenuLayout.titles
        #expect(titles.first == "File")
        for expected in ["File", "Edit", "Object", "Type", "Select", "Effect", "View", "Window", "Help"] {
            #expect(titles.contains(expected), "missing \(expected)")
        }
    }

    @Test func paramFormsAreCachedAndParse() {
        let fields = CommandCatalog.shared.params("shape.rectangle")
        #expect(!fields.isEmpty)
        #expect(CommandCatalog.shared.params("shape.rectangle").count == fields.count)
    }
}
