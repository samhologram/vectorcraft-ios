import SwiftUI
import Observation
@preconcurrency import VectorCraftKit

/// Editor state of one open document. Mirrors the engine (`DocumentHandle`) for SwiftUI, runs commands by id,
/// feeds tool events from the canvas, and mirrors engine history on the scene's `UndoManager` (CONTRACT §2, §4).
@MainActor @Observable
final class DocumentModel {
    /// The thread-safe engine object. Background work (rendering, export) calls it directly.
    @ObservationIgnored let handle: DocumentHandle

    // MARK: Engine mirror (refreshed after every call)
    var state: DocState
    var selection: SelectionInfo
    var layers: [LayerRow] = []
    /// Decoded `tool_options()`. Dictionaries have no identity for SwiftUI: observe `toolOptionsTick`.
    var toolOptions: [String: Any] = [:]
    var toolOptionsTick = 0

    /// The active tool id (== `state.tool`). Setting it selects the tool.
    var activeTool: String {
        get { state.tool }
        set { selectTool(newValue) }
    }

    // MARK: UI state shared by Core and UI
    var activePanel: Panel = .properties
    /// Set instead of `activePanel` when `window.panel` names a panel without a dedicated page (a
    /// `panel_catalog()` id such as "colorGuide"); nil when `activePanel` is the one to show.
    var activeGenericPanel: String?
    var panelGroups: [PanelGroup]
    var lastShownPanel: String?
    var panelRevealRevision = 0
    var view = ViewTransform()
    /// Shown as an alert with the full message.
    var lastError: String?
    /// Transient message ("status" UI requests).
    var statusMessage: String?
    var isDemoReady = false
    /// Set for a command that takes parameters; the UI shows a `CommandSheet`.
    var pendingCommand: String?
    var pendingParams: [String: Any] = [:]
    var showCommandPalette = false
    var showExport = false
    /// Canvas-only layout: every panel, palette, toolbar and the status bar hidden; a floating button returns.
    var isFullscreen = false
    var inspectorVisible: Bool { didSet { AppSettings.inspectorVisible = inspectorVisible } }
    /// Phone sheets are transient; the persisted iPad dock must not open one during a compact layout transition.
    var phoneSheetPresented = false
    var narrowPanelLayout = false
    var pencilOnly: Bool { didSet { AppSettings.pencilOnly = pencilOnly } }
    /// Bumps whenever the canvas must re-render the document.
    var renderTick = 0
    /// Bumps when only the overlays (tool previews, handles, hover) must be redrawn. Not in the contract:
    /// the canvas observes it so a hover move does not re-render the artwork.
    var overlayTick = 0
    @ObservationIgnored weak var undoManager: UndoManager?

    // MARK: Internals shared with the extensions
    /// True while a pointer drag, a pinch/pan or a slider drag is in flight: renders are lower resolution.
    var isInteracting: Bool { isInteractingStorage }
    var isInteractingStorage = false
    @ObservationIgnored var interactionHistoryStart: UInt64 = 0
    @ObservationIgnored var sliderDragging = false
    @ObservationIgnored var statusToken = 0
    @ObservationIgnored var pendingFit = true
    @ObservationIgnored var demoSeeded = false
    @ObservationIgnored var previousTool: String?
    /// True for a document made by File > New (the demo only seeds those).
    @ObservationIgnored var isNewDocument = false
    @ObservationIgnored var canvasPresented = false

    init(handle: DocumentHandle) {
        AppEnvironment.bootstrap()
        self.handle = handle
        state = handle.state()
        selection = handle.selection()
        pencilOnly = AppSettings.pencilOnly
        inspectorVisible = Self.initialInspectorVisible
        panelGroups = AppSettings.panelGroups
        refresh()
    }

    /// The inspector starts open on iPad (it is a sheet on iPhone, which must not pop up by itself), and always
    /// so in demo / UI-test launches, so a run never depends on what the previous one left behind.
    private static var initialInspectorVisible: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        return AppSettings.isDemo ? true : AppSettings.inspectorVisible
    }

    func setPanelLayout(narrow: Bool) {
        narrowPanelLayout = narrow
        if !narrow { phoneSheetPresented = false }
    }

    // MARK: Refresh

    /// Re-reads everything the UI shows. Call after every engine call that may have changed something.
    func refresh() {
        let new = handle.state()
        let revisionChanged = new.revision != state.revision
        let toolChanged = new.tool != state.tool
        if new != state { state = new }
        let sel = handle.selection()
        if sel != selection { selection = sel }
        if view.artboard != new.activeArtboard { view.artboard = new.activeArtboard }
        if revisionChanged || layers.isEmpty {
            let rows = handle.layers(maxRows: 5000)
            if rows != layers { layers = rows }
        }
        if revisionChanged || toolChanged { refreshToolOptions() }
        if revisionChanged { renderTick += 1 }
        overlayTick += 1
    }

    /// Re-reads `tool_options()`.
    func refreshToolOptions() {
        let options = Self.decodeObject(handle.toolOptions()) ?? [:]
        toolOptions = options
        toolOptionsTick += 1
    }

    // MARK: Running commands

    /// Executes an engine command and returns its decoded result (`[:]` when it returned nothing); errors go to
    /// `lastError` and return nil. Refreshes the mirror and registers undo. Use `run` unless the result is needed.
    @discardableResult
    func execute(_ id: String, _ params: [String: Any] = [:]) -> [String: Any]? {
        guard let json = Self.encode(params) else {
            lastError = "Could not encode the parameters of \(id)."
            return nil
        }
        let historyBefore = state.historyId
        let result: String
        do {
            result = try handle.execute(id: id, paramsJson: json)
        } catch {
            lastError = error.localizedDescription
            refresh()
            return nil
        }
        finishMutation(id: id, historyBefore: historyBefore)
        return Self.decodeObject(result) ?? [:]
    }

    /// Runs an engine command (or a UI-only / undo id) by id. Errors go to `lastError`.
    func run(_ id: String, _ params: [String: Any] = [:]) {
        switch id {
        case "edit.undo": undo(); return
        case "edit.redo": redo(); return
        default: break
        }
        if CommandCatalog.shared.isUI(id) {
            runUI(id, params)
            return
        }
        execute(id, params)
    }

    /// Executes a query command (no undo step) and returns its decoded JSON, or nil on failure / no result.
    @discardableResult
    func query(_ id: String, _ params: [String: Any] = [:]) -> Any? {
        guard let json = Self.encode(params) else {
            lastError = "Could not encode the parameters of \(id)."
            return nil
        }
        do {
            let result = try handle.execute(id: id, paramsJson: json)
            guard let data = result.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  !(value is NSNull) else { return nil }
            return value
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// After an engine call: refresh and mirror a new history step on the UndoManager.
    func finishMutation(id: String, historyBefore: UInt64) {
        refresh()
        guard !CommandCatalog.shared.isQuery(id) else { return }
        if state.historyId != historyBefore { registerUndoStep(label: state.undoLabel) }
    }

    func isEnabled(_ id: String) -> Bool {
        switch id {
        case "edit.undo": return state.canUndo
        case "edit.redo": return state.canRedo
        default: break
        }
        let catalog = CommandCatalog.shared
        if catalog.isUI(id) { return Self.implementsUI(id) }
        guard catalog.isKnown(id), catalog.isAvailable(id) else { return false }
        return handle.disabledReason(id: id) == nil
    }

    /// Menus and the palette call this: runs the command directly, or asks for its parameters first.
    func present(_ id: String, params: [String: Any] = [:]) {
        let catalog = CommandCatalog.shared
        if catalog.isUI(id) || id == "edit.undo" || id == "edit.redo" {
            run(id, params)
        } else if params.isEmpty && catalog.needsSheet(id) {
            pendingParams = [:]
            pendingCommand = id
        } else {
            run(id, params)
        }
    }

    // MARK: Status and errors

    func setStatus(_ message: String) {
        statusMessage = message
        statusToken += 1
        let token = statusToken
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))  // cancellation only ends the wait early
            guard let self, self.statusToken == token else { return }
            self.statusMessage = nil
        }
    }

    // MARK: Tool requests

    /// Handles what a tool asked the app to do (`UiRequestInfo`).
    func handleRequests(_ requests: [UiRequestInfo]) {
        for request in requests {
            switch request.kind {
            case "dialog":
                let params = Self.decodeObject(request.paramsJson) ?? [:]
                openDialog(request.value, params: params)
            case "switchTool":
                selectTool(request.value)
            case "status":
                setStatus(request.value)
            case "place":
                setStatus("Placing files is not available on iPad and iPhone yet.")
            default:
                break
            }
        }
    }

    private func openDialog(_ id: String, params: [String: Any]) {
        let catalog = CommandCatalog.shared
        if id.hasPrefix("export") || id.hasPrefix("file.export") {
            showExport = true
        } else if catalog.command(id) != nil {
            pendingParams = params
            pendingCommand = id
        } else if catalog.isUI(id) {
            runUI(id, params)
        } else {
            setStatus("Not available on iPad and iPhone yet: \(id)")
        }
    }

    // MARK: JSON

    nonisolated static func encode(_ params: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(params),
              let data = try? JSONSerialization.data(withJSONObject: params),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    /// Encodes any JSON value, fragments (numbers, strings, bools) included.
    nonisolated static func encodeValue(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    nonisolated static func decodeObject(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

extension Modifiers {
    /// No modifier keys.
    static let none = Modifiers(shift: false, alt: false, cmd: false, ctrl: false, space: false)
}
