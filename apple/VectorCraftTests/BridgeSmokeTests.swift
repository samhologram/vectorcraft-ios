import Foundation
import Testing
import VectorCraftKit

/// Smoke tests of the Rust bridge as the app sees it (CONTRACT §3): catalogs, commands, history, tools, rendering
/// and persistence. Written against the generated UniFFI bindings (snake_case -> camelCase, `mods_in` -> `mods:`).
enum BridgeFixtures {
    static func view(width: Double = 400, height: Double = 300, pixelScale: Double = 1) -> ViewParams {
        ViewParams(centerX: 540, centerY: 540, zoom: 0.5, width: width, height: height, pixelScale: pixelScale,
                   outline: false, smartGuides: false, snapToGrid: false, snapToPoint: false, showBbox: true,
                   artboard: 0)
    }

    static let noMods = Modifiers(shift: false, alt: false, cmd: false, ctrl: false, space: false)

    static func newDocument() throws -> DocumentHandle {
        try DocumentHandle.newDocument(width: 1080, height: 1080, preset: "")
    }

    static func addRectangle(_ handle: DocumentHandle, x: Double = 100, y: Double = 100) throws {
        _ = try handle.execute(id: "shape.rectangle",
                               paramsJson: "{\"x\":\(x),\"y\":\(y),\"width\":200,\"height\":120}")
    }

    static func tempPath(_ name: String) -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("vc-\(UUID().uuidString)-\(name)").path
    }
}

struct BridgeCatalogTests {
    @Test func commandCatalogsAreLoaded() {
        let commands = commandCatalog()
        #expect(commands.count > 100)
        #expect(commands.contains { $0.id == "shape.rectangle" })
        #expect(commands.allSatisfy { !$0.id.isEmpty && !$0.label.isEmpty })
        let ui = uiCommandCatalog()
        #expect(!ui.isEmpty)
        #expect(ui.contains { $0.id == "window.panel" })
        #expect(!engineVersion().isEmpty)
    }

    @Test func desktopMenuHasTheNineSections() {
        let titles = desktopMenuLayout().map(\.title)
        for expected in ["File", "Edit", "Object", "Type", "Select", "Effect", "View", "Window", "Help"] {
            #expect(titles.contains(expected), "missing menu section \(expected); got \(titles)")
        }
        #expect(titles.first == "File")
        #expect(desktopMenuLayout().allSatisfy { !$0.items.isEmpty })
    }

    @Test func toolAndPanelCatalogsAreLoaded() {
        let groups = toolCatalog()
        let tools = groups.flatMap(\.tools)
        #expect(groups.count > 10)
        #expect(tools.count > 50)
        for id in ["selection", "pen", "rectangle", "ellipse", "type", "hand", "zoom"] {
            #expect(tools.contains { $0.id == id }, "tool \(id) missing")
        }
        #expect(Set(tools.map(\.id)).count == tools.count, "tool ids must be unique")
        let panels = panelCatalog()
        #expect(panels.count > 15)
        for id in ["layers", "color", "stroke"] {
            #expect(panels.contains { $0.id == id }, "panel \(id) missing")
        }
        #expect(Set(panels.map(\.id)).count == panels.count, "panel ids must be unique")
    }

    @Test func commandParamsParse() {
        let fields = commandParams(id: "shape.rectangle")
        #expect(!fields.isEmpty)
        #expect(fields.contains { $0.key == "width" })
        _ = commandParams(id: "no.such.command")  // must not crash
    }

    @Test func platformSupportDoesNotCrashOnUnknownIds() {
        _ = commandPlatformSupport(id: "no.such.command")
        #expect(commandPlatformSupport(id: "shape.rectangle") == nil)
    }
}

struct BridgeDocumentTests {
    @Test func newDocumentStartsClean() throws {
        let handle = try BridgeFixtures.newDocument()
        let state = handle.state()
        #expect(!state.artboards.isEmpty)
        #expect(!state.canUndo)
        #expect(handle.selection().count == 0)
    }

    @Test func shapeCommandChangesStateAndHistory() throws {
        let handle = try BridgeFixtures.newDocument()
        let before = handle.state()
        let layersBefore = handle.layers(maxRows: 1000).count
        try BridgeFixtures.addRectangle(handle)
        let after = handle.state()
        #expect(after.historyId != before.historyId)
        #expect(after.revision != before.revision)
        #expect(after.canUndo)
        #expect(handle.layers(maxRows: 1000).count > layersBefore)
    }

    @Test func undoRedoMoveTheHistoryId() throws {
        let handle = try BridgeFixtures.newDocument()
        let start = handle.state().historyId
        try BridgeFixtures.addRectangle(handle)
        let added = handle.state().historyId
        #expect(added != start)
        let layersWith = handle.layers(maxRows: 1000).count
        _ = try handle.undo()
        let undone = handle.state()
        #expect(undone.historyId != added)
        #expect(undone.canRedo)
        #expect(handle.layers(maxRows: 1000).count < layersWith)
        _ = try handle.redo()
        let redone = handle.state()
        #expect(redone.historyId != undone.historyId)
        #expect(redone.canUndo)
        #expect(handle.layers(maxRows: 1000).count == layersWith)
    }

    @Test func unknownCommandThrowsInsteadOfCrashing() throws {
        let handle = try BridgeFixtures.newDocument()
        #expect(throws: (any Error).self) { try handle.execute(id: "no.such.command", paramsJson: "{}") }
        #expect(handle.disabledReason(id: "no.such.command") != nil)
        #expect(throws: (any Error).self) { try handle.execute(id: "shape.rectangle", paramsJson: "not json") }
    }

    @Test func interactionIsOneUndoStep() throws {
        let handle = try BridgeFixtures.newDocument()
        try BridgeFixtures.addRectangle(handle)
        let before = handle.state().historyId
        try handle.beginInteraction(label: "Move")
        try handle.cancelInteraction()
        #expect(handle.state().historyId == before)
    }

    @Test func stateAndSelectionAreConsistent() throws {
        let handle = try BridgeFixtures.newDocument()
        try BridgeFixtures.addRectangle(handle)
        let selection = handle.selection()
        #expect(selection.count == UInt32(selection.ids.count))
        let rows = handle.layers(maxRows: 1000)
        #expect(rows.contains { $0.selected } == (selection.count > 0))
    }
}

struct BridgeToolTests {
    @Test func rectangleToolDragCreatesAnObject() throws {
        let handle = try BridgeFixtures.newDocument()
        let view = BridgeFixtures.view()
        try handle.selectTool(id: "rectangle", view: view)
        #expect(handle.state().tool == "rectangle")
        let layersBefore = handle.layers(maxRows: 1000).count
        let historyBefore = handle.state().historyId
        _ = try handle.pointer(kind: "down", x: 200, y: 200, mods: BridgeFixtures.noMods, pressure: 1, view: view)
        for step in 1...6 {
            let t = Double(step) / 6
            _ = try handle.pointer(kind: "drag", x: 200 + 300 * t, y: 200 + 200 * t, mods: BridgeFixtures.noMods,
                                   pressure: 1, view: view)
        }
        _ = try handle.pointer(kind: "up", x: 500, y: 400, mods: BridgeFixtures.noMods, pressure: 1, view: view)
        #expect(handle.selection().count == 1)
        #expect(handle.state().historyId != historyBefore)
        #expect(handle.layers(maxRows: 1000).count == layersBefore + 1)
        #expect(!handle.state().inInteraction)
        #expect(handle.state().canUndo)
    }

    @Test func everyCatalogToolCanBeSelected() throws {
        let handle = try BridgeFixtures.newDocument()
        let view = BridgeFixtures.view()
        for tool in toolCatalog().flatMap(\.tools) {
            try handle.selectTool(id: tool.id, view: view)
            #expect(handle.state().tool == tool.id, "selecting \(tool.id)")
            _ = handle.overlays(view: view)
            _ = handle.toolOptions()
        }
    }

    @Test func selectingAnUnknownToolFailsCleanly() throws {
        let handle = try BridgeFixtures.newDocument()
        try handle.selectTool(id: "rectangle", view: BridgeFixtures.view())
        #expect(throws: (any Error).self) { try handle.selectTool(id: "no.such.tool", view: BridgeFixtures.view()) }
        #expect(handle.state().tool == "rectangle", "Invalid tool selection must not change the active tool")
    }
}

struct BridgeRenderTests {
    @Test func renderReturnsWidthHeightRGBA() throws {
        let handle = try BridgeFixtures.newDocument()
        try BridgeFixtures.addRectangle(handle)
        let view = BridgeFixtures.view(width: 320, height: 200, pixelScale: 1)
        let image = try handle.render(view: view)
        #expect(image.width == 320)
        #expect(image.height == 200)
        #expect(image.rgba.count == Int(image.width) * Int(image.height) * 4)
        #expect(image.rgba.contains { $0 != 0 }, "the render is entirely transparent")
    }

    @Test func renderHonoursPixelScale() throws {
        let handle = try BridgeFixtures.newDocument()
        let image = try handle.render(view: BridgeFixtures.view(width: 100, height: 80, pixelScale: 2))
        #expect(image.width == 200)
        #expect(image.height == 160)
        #expect(image.rgba.count == 200 * 160 * 4)
    }

    @Test func artboardThumbnailIsBounded() throws {
        let handle = try BridgeFixtures.newDocument()
        let image = try handle.renderArtboard(index: 0, maxEdge: 128)
        #expect(image.width > 0 && image.height > 0)
        #expect(max(image.width, image.height) <= 128)
        #expect(image.rgba.count == Int(image.width) * Int(image.height) * 4)
    }
}

struct BridgePersistenceTests {
    @Test func saveNativeThenOpenRoundTrips() throws {
        let handle = try BridgeFixtures.newDocument()
        try BridgeFixtures.addRectangle(handle, x: 50, y: 50)
        try BridgeFixtures.addRectangle(handle, x: 400, y: 300)
        let countBefore = handle.layers(maxRows: 1000).count
        let data = try handle.saveNative()
        #expect(data.count > 0)
        let path = BridgeFixtures.tempPath("roundtrip.vectorcraft")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try data.write(to: URL(fileURLWithPath: path))
        let reopened = try DocumentHandle.open(path: path)
        #expect(reopened.layers(maxRows: 1000).count == countBefore)
        #expect(reopened.state().artboards.count == handle.state().artboards.count)
    }

    @Test func openingGarbageThrowsInsteadOfCrashing() throws {
        let path = BridgeFixtures.tempPath("garbage.vectorcraft")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try Data("this is not a document".utf8).write(to: URL(fileURLWithPath: path))
        #expect(throws: (any Error).self) { try DocumentHandle.open(path: path) }
        #expect(throws: (any Error).self) { try DocumentHandle.open(path: "/no/such/file.vectorcraft") }
    }

    @Test func exportsProduceBytes() throws {
        let handle = try BridgeFixtures.newDocument()
        try BridgeFixtures.addRectangle(handle)
        let svg = try handle.export(format: "svg", optionsJson: "{}")
        #expect(String(decoding: svg.prefix(512), as: UTF8.self).contains("<svg"))
        let png = try handle.export(format: "png", optionsJson: "{\"scale\":0.25}")
        #expect(png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }
}
