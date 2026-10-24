import Foundation
import Testing
@preconcurrency import VectorCraftKit
@testable import VectorCraft

/// Integration tests of `DocumentModel` (CONTRACT §4) over a real engine document, without any UI.
@MainActor
struct DocumentModelTests {
    private func makeModel() throws -> DocumentModel {
        let handle = try DocumentHandle.newDocument(width: 1080, height: 1080, preset: "")
        return DocumentModel(handle: handle)
    }

    private let rectangle: [String: Any] = ["x": 100, "y": 100, "width": 200, "height": 120]

    @Test func runChangesStateAndRegistersUndo() throws {
        let model = try makeModel()
        let manager = UndoManager()
        model.undoManager = manager
        let before = model.state.historyId
        let layersBefore = model.layers.count
        model.run("shape.rectangle", rectangle)
        #expect(model.lastError == nil, "\(model.lastError ?? "")")
        #expect(model.state.historyId != before)
        #expect(model.state.canUndo)
        #expect(model.layers.count > layersBefore)
        #expect(manager.canUndo, "the engine step must be mirrored on the UndoManager")
    }

    @Test func undoAndRedoRoundTripThroughTheManager() throws {
        let model = try makeModel()
        let manager = UndoManager()
        model.undoManager = manager
        model.run("shape.rectangle", rectangle)
        #expect(manager.canUndo)
        let withShape = model.layers.count
        let historyWith = model.state.historyId
        model.undo()
        #expect(model.state.historyId != historyWith)
        #expect(model.layers.count < withShape)
        #expect(model.state.canRedo)
        model.redo()
        #expect(model.layers.count == withShape)
        #expect(model.state.canUndo)
    }

    @Test func undoWithoutAManagerStepsTheEngine() throws {
        let model = try makeModel()
        model.run("shape.rectangle", rectangle)
        let count = model.layers.count
        model.undo()
        #expect(model.layers.count < count)
    }

    @Test func unknownCommandSetsLastErrorInsteadOfCrashing() throws {
        let model = try makeModel()
        model.run("no.such.command")
        #expect(model.lastError != nil)
    }

    @Test func selectToolUpdatesTheActiveTool() throws {
        let model = try makeModel()
        model.setViewSize(CGSize(width: 400, height: 300), pixelScale: 1)
        model.selectTool("rectangle")
        #expect(model.activeTool == "rectangle")
        #expect(model.state.tool == "rectangle")
    }

    @Test func pointerEventsDrawARectangle() throws {
        let model = try makeModel()
        model.setViewSize(CGSize(width: 400, height: 300), pixelScale: 1)
        model.selectTool("rectangle")
        let layersBefore = model.layers.count
        let before = model.state.historyId
        model.pointer("down", atDocument: CGPoint(x: 200, y: 200))
        model.pointer("drag", atDocument: CGPoint(x: 350, y: 300))
        model.pointer("drag", atDocument: CGPoint(x: 500, y: 400))
        model.pointer("up", atDocument: CGPoint(x: 500, y: 400))
        #expect(model.state.historyId != before)
        #expect(model.layers.count == layersBefore + 1)
        #expect(model.selection.count == 1)
    }

    @Test func demoSeedingProducesArtAndTheReadyFlag() async throws {
        let model = try makeModel()
        model.seedDemo()
        #expect(model.layers.count >= 5, "demo seeding made \(model.layers.count) layer rows")
        #expect(model.state.canUndo)
        // The marker is raised after a short delay.
        for _ in 0..<60 where !model.isDemoReady { try await Task.sleep(for: .milliseconds(100)) }
        #expect(model.isDemoReady)
    }

    @Test func renderImageProducesAnImage() async throws {
        let model = try makeModel()
        model.setViewSize(CGSize(width: 200, height: 150), pixelScale: 1)
        model.run("shape.rectangle", rectangle)
        let image = await model.renderImage()
        #expect(image != nil)
    }

    @Test func settingsResetClearsPersistedValues() {
        UserDefaults.standard.set(true, forKey: AppSettings.Key.pencilOnly)
        let wasReset = AppSettings.shouldResetSettings
        AppSettings.prepare()
        // Under XCTest the app resets on launch; either way the call must not crash.
        if wasReset { #expect(AppSettings.pencilOnly == false) }
        UserDefaults.standard.removeObject(forKey: AppSettings.Key.pencilOnly)
    }

    @Test func phonePanelRequiresExplicitRequestAndPreservesPadDock() throws {
        let previousGroups = AppSettings.panelGroups
        defer { AppSettings.panelGroups = previousGroups }
        let model = try makeModel()
        let padDockWasVisible = model.inspectorVisible

        model.setPanelLayout(narrow: true)
        #expect(!model.phoneSheetPresented, "A compact launch must not present a sheet from iPad dock state")
        model.showPanel(named: "layers")
        #expect(model.phoneSheetPresented)
        #expect(model.activePanel == .layers)
        #expect(model.inspectorVisible == padDockWasVisible)

        model.runUI("window.panel.close")
        #expect(!model.phoneSheetPresented)
        model.showPanel(named: "layers")
        #expect(model.phoneSheetPresented, "Selecting the same panel must reopen its sheet")
        model.runUI("window.dock")
        #expect(!model.phoneSheetPresented)
        model.runUI("window.dock")
        #expect(model.phoneSheetPresented)

        model.toggleFullscreen()
        #expect(model.isFullscreen)
        #expect(!model.phoneSheetPresented)
        model.toggleFullscreen()
        #expect(!model.isFullscreen)
        #expect(model.phoneSheetPresented, "Full screen exit must restore the previously open phone sheet")

        model.setPanelLayout(narrow: false)
        #expect(!model.phoneSheetPresented)
        #expect(model.inspectorVisible == padDockWasVisible, "Resizing must retain the iPad dock setting")
    }

    @Test func sidebarTogglePreservesDockArrangementAndRevealsSelection() throws {
        let previousGroups = AppSettings.panelGroups
        let previousVisibility = AppSettings.inspectorVisible
        defer {
            AppSettings.panelGroups = previousGroups
            AppSettings.inspectorVisible = previousVisibility
        }
        let model = try makeModel()
        model.setPanelLayout(narrow: false)
        model.showDockPanel("layers")
        let groupID = try #require(model.panelGroups.first(where: { $0.tabs.contains("layers") })?.id)
        model.toggleDockGroup(groupID)
        let arranged = model.panelGroups
        let beforeReveal = model.panelRevealRevision

        model.togglePanelVisibility()
        #expect(!model.inspectorVisible)
        #expect(model.panelGroups == arranged)
        model.togglePanelVisibility()
        #expect(model.inspectorVisible)
        #expect(model.panelGroups == arranged, "Hiding and restoring must preserve selected tabs and collapse")
        #expect(model.panelRevealRevision > beforeReveal, "Restoring must reveal the selected tab")

        model.toggleFullscreen()
        #expect(model.isFullscreen)
        #expect(model.inspectorVisible)
        model.toggleFullscreen()
        #expect(!model.isFullscreen)
        #expect(model.inspectorVisible)

        model.togglePanelVisibility()
        model.showDockPanel("layers")
        #expect(model.inspectorVisible, "Menu selection must reveal a hidden dock")
        #expect(model.panelGroups.flatMap(\.tabs).filter { $0 == "layers" }.count == 1)
    }
}
