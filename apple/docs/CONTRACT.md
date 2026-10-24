# VectorCraft for iOS and iPadOS: internal contracts

Single source of truth shared by the Rust bridge, the Swift core and the Swift UI. Change it first, then the code on
both sides. Modelled on the LightCraft port (`/Users/samuelhalle/Code/LC/lightcraft-ios/apple`, read-only reference),
adapted to a vector *document* app (Linearity Curve / Affinity Designer style, see `../README.md`).

## 1. Directory ownership

| Path | Owner | What |
|---|---|---|
| `apple/bridge/` | Rust bridge | `vectorcraft-apple` crate (own `[workspace]`, UniFFI 0.32, proc-macros only) |
| `apple/scripts/` | Tooling (bridge agent) | build-xcframework, check-command-ids, tool-coverage, feature-coverage, dump-catalog |
| `apple/project.yml` | Tooling (bridge agent) | XcodeGen spec (`.xcodeproj` generated, gitignored) |
| `apple/VectorCraftKit/` | Tooling (bridge agent) | local Swift package: generated xcframework + generated Swift bindings |
| `apple/docs/catalog-dump.txt` | Tooling (bridge agent) | generated: every command id, label, menu, params doc; tools; panels (reference for Swift authors) |
| `apple/VectorCraft/Core/` | Swift core | `DocumentModel`, `VectorCraftDocument`, view transform, settings, demo seeding, catalogs |
| `apple/VectorCraft/Canvas/` | Swift core | canvas view (render, touches, Pencil, pointer, pinch/pan), overlay drawing, text input |
| `apple/VectorCraft/App/` | Swift core | `@main`, `DocumentGroup` scene, launch scene, `Commands` (menu bar) |
| `apple/VectorCraft/UI/` | Swift UI | `Shared/`, `Pad/`, `Phone/`, `Panels/`, `Commands/` |
| `apple/VectorCraft/Resources/` | Swift UI | `Assets.xcassets` (AppIcon, LaunchIcon) |
| `apple/VectorCraftTests/`, `apple/VectorCraftUITests/` | Tests | swift-testing unit tests, XCUITest UI tests + tours |
| `FORK.md`, `.github/workflows/apple-*.yml` | Tooling | fork notes, CI |

Upstream files (everything else) are never edited.

## 2. The document

`.vectorcraft` (`vectorcraft_format::EXTENSION`) is a single binary/JSON file. iOS document types:
- Exported UTType `ca.hologram.vectorcraft.document` (extension `vectorcraft`, conforms to `public.data`,
  `public.content`). Writable: only this.
- Imported, readable: `ca.hologram.vectorcraft.legacy` (`drawcraft`), `public.svg-image`, `com.adobe.pdf`,
  `com.adobe.illustrator.ai-image` (extension `ai`), `com.adobe.encapsulated-postscript` (`eps`). Opened through the
  engine importers; saved back as `.vectorcraft`.

`VectorCraftDocument: ReferenceFileDocument` (Snapshot = `Data`):
- `init()` (New): `DocumentHandle.newDocument(width: 1080, height: 1080, preset: "")` (an empty document with one
  artboard and one layer).
- `init(configuration:)`: writes `configuration.file.regularFileContents` to `Caches/Open/<uuid>/<filename>` and
  calls `DocumentHandle.open(path:)` (the engine picks the importer from the extension/content).
- `snapshot(contentType:)`: `handle.saveNative()` → `Data`. `fileWrapper(snapshot:configuration:)`:
  `FileWrapper(regularFileWithContents:)`.
- Engine history is mirrored on the scene `UndoManager`: after every call whose `historyId` changed (execute, tool
  pointer Up, commit), register an undo action calling `handle.undo()` (redo symmetric) with the engine's label as
  the action name. Never register for queries.

## 3. Rust bridge API (UniFFI, crate `vectorcraft_apple`, Swift module `VectorCraftKit`)

Swift names are what UniFFI 0.32 generates (snake_case → camelCase, `Vec<u8>` → `Data`, `u64` → `UInt64`, `u32` →
`UInt32`, `f64` → `Double`, `f32` → `Float`, `Option<T>` → `T?`, `Vec<T>` → `[T]`). Records become Swift structs
with memberwise inits in field order. Swift catches errors generically (`error.localizedDescription`). Every exported
fn runs engine code under `catch_unwind`; never panics; poisoned locks recovered.

```rust
#[derive(uniffi::Error)] pub enum BridgeError { Failed { message: String } }

// ---- catalogs (free functions) -------------------------------------------------------------
#[derive(uniffi::Record)] pub struct CommandInfo {
    pub id: String, pub label: String,
    pub menu: Vec<String>,          // ["Object","Arrange"]; empty = not in menus
    pub shortcut: Option<String>,   // egui notation "Cmd+Shift+]"
    pub params: String,             // human/agent-readable params doc
    pub is_query: bool,             // journal == false
}
// UI-only desktop commands (window.panel, tool.select, view.*, dialogs…), parsed at runtime from
// crates/ui-egui/src/menus.rs UI_COMMANDS via include_str! (no egui dependency).
#[derive(uniffi::Record)] pub struct UiCommandInfo {
    pub id: String, pub label: String, pub shortcut: Option<String>, pub params: String,
}
// Desktop menu bar, parsed from menus.rs `menu_tree_named` (c / cp / sub / Sep / todo / panel helpers).
#[derive(uniffi::Record)] pub struct MenuItemInfo {
    pub kind: String,          // "command", "separator", "submenu", "todo" (not implemented on desktop: shown disabled)
    pub label: String,
    pub command: String,       // command id for "command"; "" otherwise
    pub params_json: String,   // fixed params for cp(...) items, "{}" otherwise
    pub children: Vec<MenuItemInfo>,  // for "submenu"
}
#[derive(uniffi::Record)] pub struct MenuSection { pub title: String, pub items: Vec<MenuItemInfo> }
    // titles in desktop order: File, Edit, Object, Type, Select, Effect, View, Window, Help (the "VectorCraft"
    // app menu is dropped; its items (About, Discord) go to Help). Dynamic lists (recent files, raster effect
    // menus) are skipped, not guessed.

#[derive(uniffi::Record)] pub struct ParamField {   // structured view of a params doc; best effort
    pub key: String,      // "" = free-form extra params (label = raw fragment)
    pub kind: String,     // "number","integer","bool","choice","string","color","ids","json"
    pub min: Option<f64>, pub max: Option<f64>,
    pub default_json: Option<String>,
    pub choices: Vec<String>,
    pub label: String,    // humanized key
    pub is_optional: bool,
    pub doc: String,      // the raw fragment for this key
}
#[derive(uniffi::Record)] pub struct ToolInfo {
    pub id: String, pub label: String, pub shortcut: Option<String>,
    pub icon: String,      // upstream icon name ("tool-pen"); Swift maps to an SF Symbol
}
#[derive(uniffi::Record)] pub struct ToolGroupInfo { pub tools: Vec<ToolInfo> }  // vectorcraft_tools::TOOL_GROUPS order
#[derive(uniffi::Record)] pub struct PanelInfo {
    pub id: String,        // "layers", "colorGuide"… (the `panel` param of window.panel)
    pub label: String,     // "Layers"
    pub menu: Vec<String>, // ["Window"] or ["Window","Type"]
}

#[uniffi::export] pub fn command_catalog() -> Vec<CommandInfo>;
#[uniffi::export] pub fn ui_command_catalog() -> Vec<UiCommandInfo>;
#[uniffi::export] pub fn desktop_menu_layout() -> Vec<MenuSection>;
#[uniffi::export] pub fn command_params(id: String) -> Vec<ParamField>;
#[uniffi::export] pub fn command_platform_support(id: String) -> Option<String>; // None = supported; Some(reason) from ios-excluded-commands.txt
#[uniffi::export] pub fn tool_catalog() -> Vec<ToolGroupInfo>;
#[uniffi::export] pub fn panel_catalog() -> Vec<PanelInfo>;   // the Window menu's panel(...) entries, in menu order
#[uniffi::export] pub fn engine_version() -> String;
#[uniffi::export] pub fn configure_fonts(app_font_dir: Option<String>);
    // iOS has no font folders the engine knows (fontdb's non-macOS branch): adds /System/Library/Fonts
    // (readable on iOS) and the app's own font dir as user font dirs, then starts the background scan.
    // Idempotent. Swift calls it once at launch.

// ---- the document ----------------------------------------------------------------------------
#[derive(uniffi::Record)] pub struct ViewParams {
    pub center_x: f64, pub center_y: f64,   // document point at the centre of the view
    pub zoom: f64,                          // view points per document point (1 = 100 %)
    pub width: f64, pub height: f64,        // view size in points
    pub pixel_scale: f64,                   // device pixels per point (UIScreen scale)
    pub outline: bool,                      // View > Outline
    pub smart_guides: bool, pub snap_to_grid: bool, pub snap_to_point: bool, pub show_bbox: bool,
    pub artboard: u32,                      // active artboard index
}
    // Mapping (same as the desktop canvas): view = T(width/2, height/2) · S(zoom) · T(-center).
    // Document coordinates are y-down. Swift converts touches with the inverse.
#[derive(uniffi::Record)] pub struct Modifiers { pub shift: bool, pub alt: bool, pub cmd: bool, pub ctrl: bool, pub space: bool }
#[derive(uniffi::Record)] pub struct UiRequestInfo {
    pub kind: String,        // "dialog", "switchTool", "status", "place"
    pub value: String,       // dialog/command id, tool id, status message, "" for place
    pub params_json: String, // dialog/place params, "{}" otherwise
}
#[derive(uniffi::Record)] pub struct OverlayItem {    // vectorcraft_tools::Overlay flattened; document coords
    pub kind: String,        // "marquee","path","line","anchor","curvePoint","handle","label","measure","highlight","swatch","gridLine"
    pub points: Vec<f64>,    // x0,y0,x1,y1,… marquee: 2 corners; line/gridLine: a,b; anchor/handle/label…: 1 point;
                             // highlight: 4 corners; path: flattened polyline(s) (tolerance 0.25 view px), NaN,NaN separates subpaths
    pub rgba: Vec<u8>,       // 4 bytes
    pub width: f32, pub size: f32,
    pub dashed: bool, pub filled: bool,
    pub text: String,
}
#[derive(uniffi::Record)] pub struct RectInfo { pub x: f64, pub y: f64, pub width: f64, pub height: f64 }
#[derive(uniffi::Record)] pub struct ArtboardInfo { pub index: u32, pub name: String, pub rect: RectInfo }
#[derive(uniffi::Record)] pub struct LayerRow {       // the layer tree, flattened depth-first (top of the stack first)
    pub id: u64, pub name: String,
    pub kind: String,        // panel label: "Layer","Group","Path","Compound Path","Type","Image","Symbol"…
    pub depth: u32, pub parent: Option<u64>,
    pub visible: bool, pub locked: bool, pub selected: bool,
    pub has_children: bool,
}
#[derive(uniffi::Record)] pub struct SelectionInfo {
    pub count: u32, pub ids: Vec<u64>,
    pub bounds: Option<RectInfo>,            // geometric bounds of the selection
    pub fill: Option<String>,                // "#rrggbb" / "none" / "mixed" / "gradient" / "pattern"; None = nothing selected
    pub stroke: Option<String>,              // same
    pub stroke_width: Option<f64>,
    pub opacity: Option<f64>,                // 0..1
    pub kinds: Vec<String>,                  // distinct panel kinds in the selection
}
#[derive(uniffi::Record)] pub struct DocState {
    pub title: String,
    pub dirty: bool,
    pub artboards: Vec<ArtboardInfo>, pub active_artboard: u32,
    pub tool: String,                        // active tool id
    pub tool_wants_text: bool,               // a Type tool is editing: Swift shows the keyboard and sends tool_text
    pub in_interaction: bool,
    pub can_undo: bool, pub can_redo: bool,
    pub undo_label: Option<String>, pub redo_label: Option<String>,
    pub revision: u64,                       // bumps on every call that may change anything
    pub history_id: u64,                     // changes when an undo step is recorded, undone or redone
    pub color_mode: String,                  // "rgb" / "cmyk"
    pub fill_default: String, pub stroke_default: String,   // the toolbar's fill/stroke (new art), "#rrggbb"/"none"
}
#[derive(uniffi::Record)] pub struct RenderedImage {
    pub width: u32, pub height: u32,
    pub rgba: Vec<u8>,       // RGBA8 premultiplied, stride = width*4
}

#[derive(uniffi::Object)] pub struct DocumentHandle { /* Mutex<Inner{session, revision}> */ }
#[uniffi::export] impl DocumentHandle {
    #[uniffi::constructor] pub fn new_document(width: f64, height: f64, preset: String) -> Result<Arc<Self>, BridgeError>; // file.new
    #[uniffi::constructor] pub fn open(path: String) -> Result<Arc<Self>, BridgeError>;   // document.open {path}; any format the engine reads
    pub fn save_native(&self) -> Result<Vec<u8>, BridgeError>;      // vectorcraft_format bytes of the active document; marks saved
    pub fn export(&self, format: String, options_json: String) -> Result<Vec<u8>, BridgeError>;
        // "svg" | "pdf" | "png" (options: {scale?, artboard?, transparent?}); via the engine's export commands to a temp path, bytes returned
    pub fn execute(&self, id: String, params_json: String) -> Result<String, BridgeError>; // result JSON ("null" when none)
    pub fn disabled_reason(&self, id: String) -> Option<String>;   // None = enabled (unknown id → Some)
    pub fn undo(&self) -> Result<String, BridgeError>;              // label of the undone step
    pub fn redo(&self) -> Result<String, BridgeError>;
    pub fn begin_interaction(&self, label: String) -> Result<(), BridgeError>;   // slider drag = 1 undo step
    pub fn preview(&self, id: String, params_json: String) -> Result<String, BridgeError>;
    pub fn commit_interaction(&self) -> Result<(), BridgeError>;
    pub fn cancel_interaction(&self) -> Result<(), BridgeError>;
    pub fn state(&self) -> DocState;
    pub fn selection(&self) -> SelectionInfo;
    pub fn layers(&self, max_rows: u32) -> Vec<LayerRow>;          // capped (a huge document lists the first max_rows)
    pub fn inspect(&self, params_json: String) -> Result<String, BridgeError>;  // document.inspect passthrough
    // tools
    pub fn select_tool(&self, id: String, view: ViewParams) -> Result<(), BridgeError>;
    pub fn pointer(&self, kind: String, x: f64, y: f64, mods: Modifiers, pressure: f32, view: ViewParams) -> Result<Vec<UiRequestInfo>, BridgeError>;
        // kind: "down","drag","up","move","doubleClick"; x,y in document coords
    pub fn tool_key(&self, key: String, mods: Modifiers, view: ViewParams) -> Result<Vec<UiRequestInfo>, BridgeError>;
        // key: "enter","escape","backspace","delete","up","down","left","right","tab","home","end","[","]","0"-"9","a"-"z"
    pub fn tool_text(&self, text: String, view: ViewParams) -> Result<Vec<UiRequestInfo>, BridgeError>;
    pub fn tool_tick(&self, dt: f64, view: ViewParams) -> Result<Vec<UiRequestInfo>, BridgeError>; // while tool_wants_ticks
    pub fn tool_wants_ticks(&self) -> bool;
    pub fn tool_options(&self) -> String;                           // JSON object of the active tool's options
    pub fn set_tool_option(&self, key: String, value_json: String) -> Result<(), BridgeError>;
    pub fn overlays(&self, view: ViewParams) -> Vec<OverlayItem>;   // tool overlays + selection handles
    // rendering: snapshots the Arc<Document> under the lock, renders OUTSIDE it (call from a background task)
    pub fn render(&self, view: ViewParams) -> Result<RenderedImage, BridgeError>;
        // the view at width*pixel_scale × height*pixel_scale pixels (capped at 8192 per side), pasteboard grey
        // background, artboards white, outline per view.outline
    pub fn render_artboard(&self, index: u32, max_edge: u32) -> Result<RenderedImage, BridgeError>;  // thumbnails, export preview
}
```

Bridge files: `ui-commands.txt` (every command id the Swift sources reference literally, one per line, checked by
`scripts/check-command-ids.sh` against `command_catalog` + `ui_command_catalog`), `ios-excluded-commands.txt`
(`id<TAB>reason`, e.g. `file.reveal	no Finder on iOS`), embedded with `include_str!` for `command_platform_support`.

## 4. Swift core surface (`apple/VectorCraft/Core`, `Canvas`, `App`)

```swift
@MainActor @Observable final class DocumentModel {
    let handle: DocumentHandle
    var state: DocState                      // refreshed after every call
    var selection: SelectionInfo
    var layers: [LayerRow]
    var toolOptions: [String: Any]           // decoded tool_options() (not observed for identity; use toolOptionsTick)
    var toolOptionsTick: Int
    var activeTool: String                   // == state.tool
    var activePanel: Panel                   // inspector / sheet content
    var view: ViewTransform                  // centerX, centerY, zoom; viewSize; pixelScale; outline/snap flags
    var lastError: String?                   // shown as an alert (full message)
    var statusMessage: String?               // UiRequest "status", shown transiently
    var isDemoReady: Bool
    var pendingCommand: String?              // a command that takes params → UI shows CommandSheet
    var pendingParams: [String: Any]         // prefilled params for pendingCommand (from a tool's "dialog" request)
    var showCommandPalette: Bool
    var showExport: Bool
    var inspectorVisible: Bool               // iPad inspector column
    var showPanelSheet: Bool                 // iPhone / narrow window panel sheet
    var pencilOnly: Bool                     // "Only Draw with Apple Pencil" (AppSettings)
    var renderTick: Int                      // bumps whenever the canvas must re-render
    weak var undoManager: UndoManager?

    func run(_ id: String, _ params: [String: Any] = [:]) // execute + refresh + register undo; errors → lastError
    @discardableResult func query(_ id: String, _ params: [String: Any] = [:]) -> Any?   // execute a query command, decoded JSON
    func isEnabled(_ id: String) -> Bool
    func present(_ id: String, params: [String: Any] = [:])   // runs directly when the command needs no params, else pendingCommand = id
    func runUI(_ id: String, _ params: [String: Any] = [:])  // desktop UI-only commands: window.panel → activePanel, tool.select → selectTool, view.zoomIn/zoomOut/fitArtboard/actualSize/outline…; others → lastError "not available on iOS"
    func selectTool(_ id: String)
    func beginDrag(_ label: String); func preview(_ id: String, _ params: [String: Any]); func endDrag(); func cancelDrag()
    func setToolOption(_ key: String, _ value: Any)
    func undo(); func redo()
    func refresh()
    func fitArtboard(); func zoom(by factor: Double, around viewPoint: CGPoint); func pan(by delta: CGSize)
    func renderImage() async -> CGImage?     // current view, background task
    func artboardThumbnail(_ index: Int, edge: Int) async -> CGImage?
    func exportData(format: String, options: [String: Any]) async throws -> Data
    func seedDemo()                          // -VectorCraftDemo: shapes, star, gradient fill, type, through commands; then isDemoReady = true
}
enum Panel: String, CaseIterable, Identifiable { // rawValue == panel_catalog id
    case properties, layers, color, swatches, stroke, gradient, transparency, appearance, align, pathfinder,
         transform, artboards, character, paragraph, history, symbols, brushes, graphicStyles, docInfo, info, navigator
    // every other panel_catalog() id is reachable through `PanelHost` as a generic "commands of this panel" page
}
```

Entry views: `VectorCraftApp` (App/) builds `DocumentGroup(newDocument: { VectorCraftDocument() }) { file in
EditorRootView(model: file.document.model) }` plus `DocumentGroupLaunchScene`. `EditorRootView`
(`UI/Shared/EditorRootView.swift`, owned by UI) picks `PadEditorView` or `PhoneEditorView` by horizontal size class /
window width, hosts `CanvasView(model:)` (Core, `Canvas/CanvasView.swift`), and attaches the sheets for
`pendingCommand` (`CommandSheet`), the palette (`CommandPaletteView`), export (`ExportSheet`) and errors (alert with
the full message). It sets `model.undoManager` from `@Environment(\.undoManager)`. The menu bar (`App/EditorCommands.swift`,
Core-owned) reads the focused model through `@FocusedValue(\.documentModel)`; `EditorRootView` publishes it with
`.focusedSceneValue(\.documentModel, model)` (key declared in `Core/FocusedValues.swift`).

`CommandCatalog` (Core, `Core/CommandCatalog.swift`, a `@MainActor` singleton `CommandCatalog.shared`) wraps
`command_catalog()` + `ui_command_catalog()` + `desktop_menu_layout()` + `tool_catalog()` + `panel_catalog()`:
`menus: [MenuSection]`, `toolGroups: [ToolGroupInfo]`, `panels: [PanelInfo]`, `command(id)`, `label(id)`,
`shortcut(id) → KeyboardShortcut?`, `params(id) → [ParamField]` (cached), `needsParams(id) → Bool` (any non-optional
field), `symbol(forTool:) → String` and `symbol(forPanel:) → String` (SF Symbol names, validated against the
runtime's `name_availability.plist`).

`CanvasView` (Core): a `UIViewRepresentable` over a `UIView` that draws the rendered `CGImage` and the overlays
(`CAShapeLayer`/`CALayer` or Core Graphics), handles one-finger/Pencil touches → `model` tool pointer events
(document coords, pressure, modifiers from the hardware keyboard), hover (iPad pointer/Pencil hover) → "move",
pinch/two-finger pan → view transform, two-finger tap → undo, three-finger tap → redo, Pencil double-tap → previous
tool, and a hidden `UIKeyInput` first responder while `state.toolWantsText`. Re-renders on `renderTick`, debounced to
the display refresh; during a drag renders at reduced `pixelScale` then sharp on release.

## 5. Accessibility identifiers (UI tests drive only these)

`tool.<toolId>` (palette / strip buttons and flyout items, e.g. `tool.pen`), `toolGroup.<firstToolId>` (the group
button), `panel.<panelId>` (switcher buttons, e.g. `panel.layers`), `command.<commandId>` (every surface showing a
command: menus, context menus, the palette, context bar, sheets' Run button `command.<id>.run`),
`control.<panelId>.<field>` (inspector controls, e.g. `control.stroke.width`, `control.properties.fill`),
`param.<key>` (CommandSheet fields), `toolOption.<key>` (context bar tool options), `layer.<nodeId>`,
`artboard.<index>`, `canvas`, `inspector`, `toolPalette`, `toolStrip`, `contextBar`, `menu.<Title>` (overflow menu
sections), `undo`, `redo`, `export`, `commandPalette`, `demoReady` (hidden marker present once demo seeding finished),
`status` (status message), `errorAlert`.
Widget ids must not look like command ids (a `control.`/`param.` prefix is fine).

## 6. Panels, panel actions and the menu bar (cookbook §4 rules, 2026-10-24)

Spec:
- **Every desktop panel exists** (all `panel_catalog()` ids) and opens from both the inspector's panel menu
  (right side) and the Window menu. A panel entry that opens nothing is a bug; the panel tour opens AND acts on every
  panel.
- **Arrangement like the desktop**: on iPad the inspector holds a *stack* of panels; each can be added (panel menu /
  Window menu), hidden (closed), collapsed to its header, and reordered by dragging its header. The arrangement
  (ordered ids + collapsed flags) persists in `AppSettings` and is reset by `-VectorCraftResetSettings`.
  iPhone: one panel per sheet (detents), the panel menu picks which. Model surface (to add):
  `var panelStack: [PanelSlot]` (`struct PanelSlot { id: String; collapsed: Bool }`), `showPanel(_ id:)` (adds or
  expands + scrolls to it), `hidePanel(_ id:)`, `togglePanelCollapsed(_ id:)`, `movePanel(from:to:)`.
  Ids: `panel.<id>` (menu entries), `panelHeader.<id>` (collapse toggle), `panelClose.<id>`, `panelBody.<id>`.
- **Panel-owned actions live in the panel header** (a trailing button row / "…" menu in `panelHeader.<id>`): Layers
  (new layer, new sublayer, delete, locate), Swatches (new swatch, delete), Artboards (new, delete), Symbols / Brushes /
  Graphic Styles (new from selection, delete), Appearance (add fill, add stroke, add effect). Never in the global
  toolbar or context bar.
- **iPad menu bar = merge**: iPadOS system groups stay (app menu, File, Edit, View, Window, Help); the desktop menus and
  items are inserted in desktop order (File items into File, Edit into Edit, then Object, Type, Select, Effect, View
  items into View), Window and Help last.

Current state vs. spec (as of commit dd935321; to fix after the hold):
1. No panel stack: the inspector shows ONE panel (`DocumentModel.activePanel` + `activeGenericPanel`); no add/hide/
   collapse/reorder, nothing persisted besides `inspectorVisible`.
2. Panel actions sit in panel *bodies*, not headers: `LayersPanel.swift` (layer.new / layer.newSublayer / layer.delete),
   `ColorPanels.swift` (swatch.new), `ArtboardsPanel.swift` (artboard.new), `LibraryPanels.swift` (symbol.new,
   brush.new, graphicStyle.new). There is no shared panel header view yet.
3. `UI/Pad/ContextBar.swift` carries selection actions owned by panels (Align, Pathfinder, Arrange): keep the tool
   options there; move or duplicate the panel actions into their panels' headers (decide per HIG: context bar quick
   actions may stay only as shortcuts, the panel must own them).
4. 21 panels are hand-built; the other `panel_catalog()` ids open a generic "commands of this panel" page. Verify each
   generic page has at least one working action (tour requirement); panels whose page is empty count as bugs.
5. Menu bar (`App/EditorCommands.swift`): File/Edit/View/Window/Help items are merged into the system groups, but
   Object/Type/Select/Effect are `CommandMenu`s, which iPadOS places after View, not in desktop order between Edit and
   View. Fix by checking iPadOS ordering of `CommandMenu` vs `CommandGroup(after: .textEditing)` placement, else note
   the platform limitation in a code comment.

## 7. Productivity, Apple-clean (cookbook §0b, 2026-10-24)

Spec — fast:
- Every frequent action ≤ 1 tap from the canvas (tool pick, fill/stroke, undo/redo, delete, group, duplicate,
  arrange, align, zoom-to-fit, the last command).
- Hardware keyboard: every desktop shortcut with the same keys (tools V/A/P/T/M/L…, menu shortcuts from the catalog,
  Space-drag pans, ⌘+/⌘−/⌘0 zoom), ⌘K opens the command palette.
- Context menus on canvas objects (long-press / secondary click: cut/copy/paste/duplicate/delete/group/arrange/lock/
  hide), on layer rows, artboard rows, swatches.
- Drag & drop: layer reorder, images/SVG/PDF dropped onto the canvas (place), swatches onto objects, share out.
- Gestures: two-finger tap undo, three-finger tap redo, pinch/pan; Pencil double-tap and squeeze (previous tool /
  tool palette at the tip), Pencil hover shows the tool preview.
- Scrubbable numeric fields (drag the label to change the value, one undo step), units shown.
- Customizable toolbar (`toolbar(id:)` + `ToolbarItem(id:)`), remembered last tool, panel layout, tool options and
  dialog values (`AppSettings`, reset by `-VectorCraftResetSettings`); multiple windows (one document per scene).
Spec — clean: system components, SF Symbols, semantic colours, one primary action per area; everything else in menus,
panel headers (§6) or the palette; no custom chrome.
Feature pass deliverable: taps-to-do for the top 10 vector workflows (draw shape + set fill, pen path, edit anchors,
type, align 3 objects, boolean unite, group + arrange, gradient fill, export PNG, new artboard).

Current state vs. spec (commit 11f68b1c, by grep, not run):
1. No ⌘K: the palette has a toolbar button but no keyboard shortcut.
2. Context menus only on Layers and Artboards rows; none on canvas objects or swatches.
3. Drag & drop only for layer reorder; no drop onto the canvas (place), no swatch drag.
4. Toolbar not customizable (no `toolbar(id:)`).
5. Remembered state: only `pencilOnly` and `inspectorVisible`; last tool, panel layout, tool options and dialog values
   are not persisted.
6. Scrub: `DragSlider` exists in 4 places; numeric fields (`NumberField`, transform X/Y/W/H, stroke weight) are not
   scrubbable.
7. Present: two/three-finger undo/redo taps, Pencil double-tap and squeeze (previous tool), hover → "move" events,
   single-key tool shortcuts, desktop menu shortcuts via the generated menu bar, DocumentGroup multi-window.
8. Not yet verified: Space-drag pan and ⌘+/⌘−/⌘0 zoom on a hardware keyboard; taps-to-do for the top 10 workflows.

## 8. Start from / import device media (cookbook §0b, 2026-10-24)

Spec: a new document can start from an image, SVG or PDF (document browser import + a "New from Photo/File" entry
in the new-document flow: the engine opens SVG/PDF directly; an image becomes a document sized to it with the image
placed via `file.place`). Into the current document (active artboard, selected/current layer), place from the camera
roll (`PhotosPicker`, image data written to a temp file → `file.place {path}`), Files/iCloud (`fileImporter`, security-
scoped URL copied to a temp file), drag & drop onto the canvas, and paste (images/SVG/PDF from the pasteboard).
Entry points: new-document flow, Layers panel header "Place", File ▸ Place…, ⌘K palette, canvas context menu.
Ids: `control.place.photos`, `control.place.files`, `command.file.place`. Needs `NSPhotoLibraryUsageDescription` only if
full library access is requested (PhotosPicker needs none).

Native decoders: photos and raster files (HEIC, JPEG, PNG, TIFF, RAW…) decode with ImageIO / Core Image (orientation and
colour applied) and reach the engine as pixels through a new bridge call `place_image(rgba: Vec<u8>, width, height,
name, artboard)` (to add); PDF pages for raster use go through PDFKit. Engine importers only for formats it owns as
vector/native (`.vectorcraft`, SVG, PDF-as-vector, AI, EPS, DXF…).

Current state (commit 6de1bdda, by grep): none of it — no PhotosPicker, no fileImporter, `file.place` not wired
(it appears only in the generated File menu, where its path param has no picker), no paste or canvas drop of media.
Document browser already opens SVG/PDF/AI/EPS/legacy files as new documents (§2).

## 9. App folder and foreign formats (cookbook §0b, 2026-10-24)

Documents live in iCloud Drive › VectorCraft (ubiquity container `iCloud.ca.hologram.vectorcraft`, `Documents/`),
falling back to On My iPad › VectorCraft without iCloud; it is the launch browser's default location. Opening a foreign
format (SVG, PDF, AI, EPS, `.drawcraft`, PNG/JPEG…) creates a native `.vectorcraft` copy there (saved on first edit,
original untouched; reopening the same original reopens its copy, keyed by the original's bookmark/URL); Export/Share
writes foreign formats. Current state: not implemented (foreign files open read-only through DocumentGroup's
import path; no iCloud container or entitlement yet).
