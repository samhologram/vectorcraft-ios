//! UniFFI bridge between the VectorCraft engine and the Swift app (iOS / iPadOS).
//!
//! The API is specified in `apple/docs/CONTRACT.md` section 3; names and types here match it.
//! Never panics on input: engine calls run under `catch_unwind` as a last-resort guard.
#![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, PoisonError};

use serde_json::{Value, json};
use vectorcraft_engine::{Session, UiRequest, ViewInfo};
use vectorcraft_tools::{Mods, Overlay, PointerEvent, PointerKind, ToolKey};

mod effects_menu;
mod info;
pub mod menus_src;
pub mod params_doc;
mod render;

uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum BridgeError {
    #[error("{message}")]
    Failed { message: String },
}

pub(crate) fn fail(message: impl Into<String>) -> BridgeError {
    BridgeError::Failed { message: message.into() }
}

// ---------------------------------------------------------------------------------------------
// Records
// ---------------------------------------------------------------------------------------------

#[derive(uniffi::Record)]
pub struct CommandInfo {
    pub id: String,
    pub label: String,
    /// e.g. ["Object", "Arrange"]; empty = not in menus.
    pub menu: Vec<String>,
    /// egui notation, "Cmd+Shift+]".
    pub shortcut: Option<String>,
    /// Human/agent-readable params doc.
    pub params: String,
    /// `journal == false`.
    pub is_query: bool,
}

/// UI-only desktop commands, parsed from `crates/ui-egui/src/menus.rs`.
#[derive(uniffi::Record)]
pub struct UiCommandInfo {
    pub id: String,
    pub label: String,
    pub shortcut: Option<String>,
    pub params: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct MenuItemInfo {
    /// "command", "separator", "submenu", "todo".
    pub kind: String,
    pub label: String,
    pub command: String,
    pub params_json: String,
    pub children: Vec<MenuItemInfo>,
}

#[derive(uniffi::Record)]
pub struct MenuSection {
    pub title: String,
    pub items: Vec<MenuItemInfo>,
}

/// Structured view of a params doc; best effort.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ParamField {
    /// "" = free-form extra params (`doc` = raw fragment).
    pub key: String,
    /// "number", "integer", "bool", "choice", "string", "color", "ids", "json".
    pub kind: String,
    pub min: Option<f64>,
    pub max: Option<f64>,
    pub default_json: Option<String>,
    pub choices: Vec<String>,
    pub label: String,
    pub is_optional: bool,
    pub doc: String,
}

#[derive(uniffi::Record)]
pub struct ToolInfo {
    pub id: String,
    pub label: String,
    pub shortcut: Option<String>,
    pub icon: String,
}

#[derive(uniffi::Record)]
pub struct ToolGroupInfo {
    pub tools: Vec<ToolInfo>,
}

#[derive(uniffi::Record)]
pub struct PanelInfo {
    pub id: String,
    pub label: String,
    pub menu: Vec<String>,
}

#[derive(uniffi::Record)]
pub struct ViewParams {
    pub center_x: f64,
    pub center_y: f64,
    pub zoom: f64,
    pub width: f64,
    pub height: f64,
    pub pixel_scale: f64,
    pub outline: bool,
    pub smart_guides: bool,
    pub snap_to_grid: bool,
    pub snap_to_point: bool,
    pub show_bbox: bool,
    pub artboard: u32,
}

#[derive(uniffi::Record)]
pub struct Modifiers {
    pub shift: bool,
    pub alt: bool,
    pub cmd: bool,
    pub ctrl: bool,
    pub space: bool,
}

#[derive(uniffi::Record)]
pub struct UiRequestInfo {
    /// "dialog", "switchTool", "status", "place".
    pub kind: String,
    pub value: String,
    pub params_json: String,
}

#[derive(uniffi::Record)]
pub struct OverlayItem {
    pub kind: String,
    pub points: Vec<f64>,
    pub rgba: Vec<u8>,
    pub width: f32,
    pub size: f32,
    pub dashed: bool,
    pub filled: bool,
    pub text: String,
}

#[derive(uniffi::Record)]
pub struct RectInfo {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(uniffi::Record)]
pub struct ArtboardInfo {
    pub index: u32,
    pub name: String,
    pub rect: RectInfo,
}

#[derive(uniffi::Record)]
pub struct LayerRow {
    pub id: u64,
    pub name: String,
    pub kind: String,
    pub depth: u32,
    pub parent: Option<u64>,
    pub visible: bool,
    pub locked: bool,
    pub selected: bool,
    pub has_children: bool,
}

#[derive(uniffi::Record)]
pub struct SelectionInfo {
    pub count: u32,
    pub ids: Vec<u64>,
    pub bounds: Option<RectInfo>,
    pub fill: Option<String>,
    pub stroke: Option<String>,
    pub stroke_width: Option<f64>,
    pub opacity: Option<f64>,
    pub kinds: Vec<String>,
}

#[derive(uniffi::Record)]
pub struct DocState {
    pub title: String,
    pub dirty: bool,
    pub artboards: Vec<ArtboardInfo>,
    pub active_artboard: u32,
    pub tool: String,
    pub tool_wants_text: bool,
    pub in_interaction: bool,
    pub can_undo: bool,
    pub can_redo: bool,
    pub undo_label: Option<String>,
    pub redo_label: Option<String>,
    pub revision: u64,
    pub history_id: u64,
    pub color_mode: String,
    pub fill_default: String,
    pub stroke_default: String,
}

#[derive(uniffi::Record)]
pub struct RenderedImage {
    pub width: u32,
    pub height: u32,
    /// RGBA8 premultiplied, stride = width * 4.
    pub rgba: Vec<u8>,
}

// ---------------------------------------------------------------------------------------------
// Handle
// ---------------------------------------------------------------------------------------------

/// What identifies the undo/redo stacks: lengths and the top entries' labels and sizes.
type HistorySig = (usize, usize, Option<(String, usize)>, Option<(String, usize)>);

struct Inner {
    session: Session,
    revision: u64,
    history_id: u64,
    history_sig: HistorySig,
    artboard: u32,
}

impl Inner {
    fn new(session: Session) -> Self {
        let sig = Self::sig(&session);
        Inner { session, revision: 1, history_id: 1, history_sig: sig, artboard: 0 }
    }

    fn sig(s: &Session) -> HistorySig {
        match s.active() {
            Some(d) => (
                d.history.undo.len(),
                d.history.redo.len(),
                d.history.undo.last().map(|e| (e.label.clone(), e.bytes)),
                d.history.redo.last().map(|e| (e.label.clone(), e.bytes)),
            ),
            None => (0, 0, None, None),
        }
    }

    /// Bump `history_id` when the undo/redo stacks moved since the last look.
    fn sync_history(&mut self) {
        let sig = Self::sig(&self.session);
        if sig != self.history_sig {
            self.history_sig = sig;
            self.history_id += 1;
        }
    }

    fn touch(&mut self) {
        self.revision += 1;
        self.sync_history();
    }

    fn view(&mut self, v: &ViewParams) -> ViewInfo {
        self.artboard = v.artboard;
        view_info(v)
    }
}

fn view_info(v: &ViewParams) -> ViewInfo {
    ViewInfo {
        zoom: if v.zoom.is_finite() && v.zoom > 0.0 { v.zoom } else { 1.0 },
        outline: v.outline,
        smart_guides: v.smart_guides,
        snap_to_grid: v.snap_to_grid,
        show_bbox: v.show_bbox,
        snap_to_point: v.snap_to_point,
        artboard: v.artboard as usize,
        ..ViewInfo::default()
    }
}

fn mods(m: &Modifiers) -> Mods {
    Mods { shift: m.shift, alt: m.alt, cmd: m.cmd, ctrl: m.ctrl, space: m.space }
}

#[derive(uniffi::Object)]
pub struct DocumentHandle {
    inner: Mutex<Inner>,
    /// Kept apart from the session so a render never holds the session lock.
    renderer: Mutex<vectorcraft_render::Renderer>,
}

pub(crate) fn panic_message(payload: &(dyn std::any::Any + Send)) -> String {
    let text = payload.downcast_ref::<&str>().map(|s| (*s).to_string()).or_else(|| payload.downcast_ref::<String>().cloned());
    format!("internal error: {}", text.unwrap_or_else(|| "the engine panicked".into()))
}

fn parse_params(params_json: &str) -> Result<Value, BridgeError> {
    if params_json.trim().is_empty() {
        return Ok(json!({}));
    }
    serde_json::from_str(params_json).map_err(|e| fail(format!("params_json is not valid JSON: {e}")))
}

fn requests(r: Vec<UiRequest>) -> Vec<UiRequestInfo> {
    r.into_iter()
        .map(|q| match q {
            UiRequest::Dialog(id, p) => UiRequestInfo { kind: "dialog".into(), value: id, params_json: p.to_string() },
            UiRequest::SwitchTool(id) => UiRequestInfo { kind: "switchTool".into(), value: id, params_json: "{}".into() },
            UiRequest::Status(m) => UiRequestInfo { kind: "status".into(), value: m, params_json: "{}".into() },
            UiRequest::Place(p) => UiRequestInfo { kind: "place".into(), value: String::new(), params_json: p.to_string() },
        })
        .collect()
}

impl DocumentHandle {
    fn wrap(session: Session) -> Arc<Self> {
        Arc::new(Self { inner: Mutex::new(Inner::new(session)), renderer: Mutex::new(vectorcraft_render::Renderer::new()) })
    }

    /// Run `f` with the session locked, turning a panic into an error.
    fn guarded<T>(&self, f: impl FnOnce(&mut Inner) -> Result<T, BridgeError>) -> Result<T, BridgeError> {
        let mut guard = self.inner.lock().unwrap_or_else(PoisonError::into_inner);
        match catch_unwind(AssertUnwindSafe(|| f(&mut guard))) {
            Ok(r) => r,
            Err(payload) => Err(fail(panic_message(payload.as_ref()))),
        }
    }

    /// Like [`Self::guarded`] for calls that cannot report an error.
    fn guarded_or<T>(&self, fallback: T, f: impl FnOnce(&mut Inner) -> T) -> T {
        let mut guard = self.inner.lock().unwrap_or_else(PoisonError::into_inner);
        catch_unwind(AssertUnwindSafe(|| f(&mut guard))).unwrap_or(fallback)
    }

    /// Execute a command, bumping the revision (and history id when it moved).
    fn run(inner: &mut Inner, id: &str, params: &Value) -> Result<Value, BridgeError> {
        let mutates = vectorcraft_engine::find_command(id).is_none_or(|c| c.journal);
        let r = inner.session.execute(id, params);
        if mutates {
            inner.touch();
        } else {
            inner.sync_history();
        }
        r.map_err(|e| fail(e.to_string()))
    }

    fn tool_call(&self, view: &ViewParams, f: impl FnOnce(&mut Session, ViewInfo) -> vectorcraft_engine::Result<Vec<UiRequest>>) -> Result<Vec<UiRequestInfo>, BridgeError> {
        self.guarded(|i| {
            let v = i.view(view);
            let r = f(&mut i.session, v);
            i.touch();
            r.map(requests).map_err(|e| fail(e.to_string()))
        })
    }
}

#[uniffi::export]
impl DocumentHandle {
    /// A new document (`file.new`) with one artboard and one layer. `preset` "" = none.
    #[uniffi::constructor]
    pub fn new_document(width: f64, height: f64, preset: String) -> Result<Arc<Self>, BridgeError> {
        let h = Self::wrap(Session::new());
        h.guarded(|i| {
            let mut p = serde_json::Map::new();
            if !preset.is_empty() {
                p.insert("preset".into(), json!(preset));
            }
            if width.is_finite() && height.is_finite() && width > 0.0 && height > 0.0 {
                p.insert("width".into(), json!(width));
                p.insert("height".into(), json!(height));
                p.insert("units".into(), json!("Pixels"));
            }
            Self::run(i, "file.new", &Value::Object(p))?;
            // A fresh document is saved-clean: nothing to save yet.
            Ok(())
        })?;
        Ok(h)
    }

    /// `document.open {path}`: any format the engine reads.
    #[uniffi::constructor]
    pub fn open(path: String) -> Result<Arc<Self>, BridgeError> {
        let h = Self::wrap(Session::new());
        h.guarded(|i| {
            Self::run(i, "document.open", &json!({ "path": path }))?;
            Ok(())
        })?;
        Ok(h)
    }

    /// The `.vectorcraft` bytes of the active document; marks it saved.
    pub fn save_native(&self) -> Result<Vec<u8>, BridgeError> {
        self.guarded(|i| {
            let st = i.session.doc_mut().map_err(|e| fail(e.to_string()))?;
            let bytes = vectorcraft_format::save_file(&st.doc);
            st.mark_saved();
            i.touch();
            Ok(bytes)
        })
    }

    /// "svg" | "pdf" | "png" (options `{scale?, artboard?, transparent?}`, others pass through to
    /// `document.serialize`). Returns the file bytes.
    pub fn export(&self, format: String, options_json: String) -> Result<Vec<u8>, BridgeError> {
        let opts = parse_params(&options_json)?;
        let mut p = opts.as_object().cloned().unwrap_or_default();
        let transparent = p.remove("transparent").and_then(|v| v.as_bool()).unwrap_or(false);
        p.insert("format".into(), json!(format));
        if matches!(format.as_str(), "png" | "webp" | "gif") && !p.contains_key("background") {
            p.insert("background".into(), json!(if transparent { "transparent" } else { "white" }));
        }
        self.guarded(|i| {
            let r = Self::run(i, "document.serialize", &Value::Object(p))?;
            if let Some(b64) = r.get("dataBase64").and_then(Value::as_str) {
                return vectorcraft_format::base64_decode(b64).ok_or_else(|| fail("the export produced invalid data"));
            }
            match r.get("text").and_then(Value::as_str) {
                Some(t) => Ok(t.as_bytes().to_vec()),
                None => Err(fail("the export produced no data")),
            }
        })
    }

    /// Run a command by id with JSON params; returns the result JSON.
    pub fn execute(&self, id: String, params_json: String) -> Result<String, BridgeError> {
        let params = parse_params(&params_json)?;
        self.guarded(|i| Self::run(i, &id, &params).map(|v| v.to_string()))
    }

    /// `None` = enabled. Unknown ids are reported as disabled.
    pub fn disabled_reason(&self, id: String) -> Option<String> {
        self.guarded_or(Some("internal error".to_string()), |i| match vectorcraft_engine::find_command(&id) {
            None => Some(format!("unknown command `{id}`")),
            Some(spec) => (spec.enabled)(&i.session).err(),
        })
    }

    /// Label of the undone step.
    pub fn undo(&self) -> Result<String, BridgeError> {
        self.guarded(|i| {
            let label = i.session.active().and_then(|d| d.history.undo.last().map(|e| e.label.clone())).unwrap_or_default();
            Self::run(i, "edit.undo", &json!({}))?;
            Ok(label)
        })
    }

    pub fn redo(&self) -> Result<String, BridgeError> {
        self.guarded(|i| {
            let label = i.session.active().and_then(|d| d.history.redo.last().map(|e| e.label.clone())).unwrap_or_default();
            Self::run(i, "edit.redo", &json!({}))?;
            Ok(label)
        })
    }

    /// Start a continuous edit (slider drag): everything until `commit_interaction` is one undo step.
    pub fn begin_interaction(&self, label: String) -> Result<(), BridgeError> {
        self.guarded(|i| {
            let r = i.session.begin_interaction(&label);
            i.touch();
            r.map_err(|e| fail(e.to_string()))
        })
    }

    pub fn preview(&self, id: String, params_json: String) -> Result<String, BridgeError> {
        let params = parse_params(&params_json)?;
        self.guarded(|i| {
            let r = i.session.preview(&id, &params);
            i.touch();
            r.map(|v| v.to_string()).map_err(|e| fail(e.to_string()))
        })
    }

    pub fn commit_interaction(&self) -> Result<(), BridgeError> {
        self.guarded(|i| {
            let r = i.session.commit_interaction();
            i.touch();
            r.map_err(|e| fail(e.to_string()))
        })
    }

    pub fn cancel_interaction(&self) -> Result<(), BridgeError> {
        self.guarded(|i| {
            let r = i.session.cancel_interaction();
            i.touch();
            r.map_err(|e| fail(e.to_string()))
        })
    }

    pub fn state(&self) -> DocState {
        let fallback = DocState {
            title: String::new(),
            dirty: false,
            artboards: Vec::new(),
            active_artboard: 0,
            tool: String::new(),
            tool_wants_text: false,
            in_interaction: false,
            can_undo: false,
            can_redo: false,
            undo_label: None,
            redo_label: None,
            revision: 0,
            history_id: 0,
            color_mode: "rgb".into(),
            fill_default: "#ffffff".into(),
            stroke_default: "#000000".into(),
        };
        self.guarded_or(fallback, |i| {
            i.sync_history();
            info::doc_state(i)
        })
    }

    pub fn selection(&self) -> SelectionInfo {
        self.guarded_or(info::empty_selection(), |i| info::selection(&i.session))
    }

    pub fn layers(&self, max_rows: u32) -> Vec<LayerRow> {
        self.guarded_or(Vec::new(), |i| info::layers(&i.session, max_rows as usize))
    }

    /// `document.inspect` passthrough.
    pub fn inspect(&self, params_json: String) -> Result<String, BridgeError> {
        let params = parse_params(&params_json)?;
        self.guarded(|i| Self::run(i, "document.inspect", &params).map(|v| v.to_string()))
    }

    pub fn select_tool(&self, id: String, view: ViewParams) -> Result<(), BridgeError> {
        // The desktop engine falls back to Selection for an unknown ID. The native bridge is
        // catalog-driven, so reject that request before it changes the active tool.
        if vectorcraft_tools::tool_info(&id).is_none() {
            return Err(fail(format!("unknown tool `{id}`")));
        }
        self.guarded(|i| {
            let v = i.view(&view);
            let r = i.session.select_tool(&id, v);
            i.touch();
            r.map_err(|e| fail(e.to_string()))
        })
    }

    /// kind: "down","drag","up","move","doubleClick"; x, y in document coordinates.
    pub fn pointer(&self, kind: String, x: f64, y: f64, mods: Modifiers, pressure: f32, view: ViewParams) -> Result<Vec<UiRequestInfo>, BridgeError> {
        let kind = match kind.as_str() {
            "down" => PointerKind::Down,
            "drag" => PointerKind::Drag,
            "up" => PointerKind::Up,
            "move" => PointerKind::Move,
            "doubleClick" => PointerKind::DoubleClick,
            other => return Err(fail(format!("unknown pointer kind `{other}`"))),
        };
        if !x.is_finite() || !y.is_finite() {
            return Err(fail("pointer position is not finite"));
        }
        let pressure = if pressure.is_finite() { pressure.clamp(0.0, 1.0) } else { 1.0 };
        let mut ev = PointerEvent::new(kind, x, y).with_mods(self::mods(&mods));
        ev.pressure = pressure;
        self.tool_call(&view, |s, v| s.pointer(&ev, v))
    }

    /// key: "enter","escape","backspace","delete","up","down","left","right","tab","home","end","[","]","0"-"9","a"-"z".
    pub fn tool_key(&self, key: String, mods: Modifiers, view: ViewParams) -> Result<Vec<UiRequestInfo>, BridgeError> {
        let k = parse_key(&key).ok_or_else(|| fail(format!("unknown key `{key}`")))?;
        let m = self::mods(&mods);
        self.tool_call(&view, |s, v| s.tool_key(k, m, v))
    }

    pub fn tool_text(&self, text: String, view: ViewParams) -> Result<Vec<UiRequestInfo>, BridgeError> {
        self.tool_call(&view, |s, v| s.tool_text(&text, v))
    }

    /// While `tool_wants_ticks`.
    pub fn tool_tick(&self, dt: f64, view: ViewParams) -> Result<Vec<UiRequestInfo>, BridgeError> {
        let dt = if dt.is_finite() { dt.clamp(0.0, 60.0) } else { 0.0 };
        self.tool_call(&view, |s, v| s.tool_tick(dt, v))
    }

    pub fn tool_wants_ticks(&self) -> bool {
        self.guarded_or(false, |i| i.session.tool_wants_ticks())
    }

    /// JSON object of the active tool's options.
    pub fn tool_options(&self) -> String {
        self.guarded_or("{}".to_string(), |i| i.session.tool_options().to_string())
    }

    pub fn set_tool_option(&self, key: String, value_json: String) -> Result<(), BridgeError> {
        let v = parse_params(&value_json)?;
        self.guarded(|i| {
            i.session.set_tool_option(&key, &v);
            i.touch();
            Ok(())
        })
    }

    /// Tool overlays and selection handles, flattened; document coordinates.
    pub fn overlays(&self, view: ViewParams) -> Vec<OverlayItem> {
        self.guarded_or(Vec::new(), |i| {
            let v = i.view(&view);
            let ov = i.session.overlays(v);
            flatten_overlays(&ov, v.zoom)
        })
    }

    /// The view at width*pixel_scale x height*pixel_scale pixels (capped at 8192 per side). Renders
    /// outside the session lock: call from a background task.
    pub fn render(&self, view: ViewParams) -> Result<RenderedImage, BridgeError> {
        let doc = self.guarded(|i| i.session.active().map(|d| d.doc.clone()).ok_or_else(|| fail("no document")))?;
        let (w, h) = render::pixel_size(&view);
        let affine = render::view_affine(&view, w, h);
        let opts = render::screen_options(&view);
        let mut r = self.renderer.lock().unwrap_or_else(PoisonError::into_inner);
        let out = catch_unwind(AssertUnwindSafe(|| r.render(&doc, w, h, affine, &opts))).map_err(|p| fail(panic_message(p.as_ref())))?;
        render::to_image(out)
    }

    /// An artboard fitted into `max_edge` pixels on its long side, white background.
    pub fn render_artboard(&self, index: u32, max_edge: u32) -> Result<RenderedImage, BridgeError> {
        let doc = self.guarded(|i| i.session.active().map(|d| d.doc.clone()).ok_or_else(|| fail("no document")))?;
        let ab = doc.artboards.get(index as usize).ok_or_else(|| fail(format!("no artboard {index}")))?;
        let rect = ab.rect;
        let edge = max_edge.clamp(1, 8192) as f64;
        let long = rect.width().max(rect.height());
        if !(long.is_finite() && long > 0.0) {
            return Err(fail("the artboard is empty"));
        }
        let opts = vectorcraft_render::RenderOptions { background: Some([255, 255, 255, 255]), artboards: false, skip_templates: true, smooth_images: true, ..Default::default() };
        let mut r = self.renderer.lock().unwrap_or_else(PoisonError::into_inner);
        let out = catch_unwind(AssertUnwindSafe(|| r.render_region_with(&doc, rect, edge / long, &opts))).map_err(|p| fail(panic_message(p.as_ref())))?;
        render::to_image(out)
    }
}

fn parse_key(key: &str) -> Option<ToolKey> {
    Some(match key {
        "enter" => ToolKey::Enter,
        "escape" => ToolKey::Escape,
        "backspace" => ToolKey::Backspace,
        "delete" => ToolKey::Delete,
        "up" => ToolKey::Up,
        "down" => ToolKey::Down,
        "left" => ToolKey::Left,
        "right" => ToolKey::Right,
        "tab" => ToolKey::Tab,
        "home" => ToolKey::Home,
        "end" => ToolKey::End,
        "[" => ToolKey::BracketLeft,
        "]" => ToolKey::BracketRight,
        k => {
            let mut it = k.chars();
            let c = it.next()?;
            if it.next().is_some() {
                return None;
            }
            if let Some(d) = c.to_digit(10) {
                ToolKey::Digit(u8::try_from(d).ok()?)
            } else if c.is_ascii_alphabetic() {
                ToolKey::Letter(c.to_ascii_lowercase())
            } else {
                return None;
            }
        }
    })
}

fn flatten_overlays(ov: &[Overlay], zoom: f64) -> Vec<OverlayItem> {
    let tol = 0.25 / zoom.max(1e-9);
    let item = |kind: &str, points: Vec<f64>, rgba: [u8; 4]| OverlayItem {
        kind: kind.into(),
        points,
        rgba: rgba.to_vec(),
        width: 1.0,
        size: 0.0,
        dashed: false,
        filled: false,
        text: String::new(),
    };
    let rgb = |c: [u8; 3]| [c[0], c[1], c[2], 255];
    ov.iter()
        .map(|o| match o {
            Overlay::Marquee(r) => item("marquee", vec![r.x0, r.y0, r.x1, r.y1], [0, 0, 0, 255]),
            Overlay::Path { path, color, width, dashed } => {
                let mut pts: Vec<f64> = Vec::new();
                let mut start = (0.0, 0.0);
                kurbo::flatten(path.iter(), tol, |el| match el {
                    kurbo::PathEl::MoveTo(p) => {
                        if !pts.is_empty() {
                            pts.extend([f64::NAN, f64::NAN]);
                        }
                        start = (p.x, p.y);
                        pts.extend([p.x, p.y]);
                    }
                    kurbo::PathEl::LineTo(p) => pts.extend([p.x, p.y]),
                    kurbo::PathEl::ClosePath => pts.extend([start.0, start.1]),
                    _ => {}
                });
                OverlayItem { width: *width, dashed: *dashed, ..item("path", pts, rgb(*color)) }
            }
            Overlay::Line { a, b, color, dashed } => OverlayItem { dashed: *dashed, ..item("line", vec![a.x, a.y, b.x, b.y], rgb(*color)) },
            Overlay::Anchor { p, color, filled, size } => OverlayItem { filled: *filled, size: *size, ..item("anchor", vec![p.x, p.y], rgb(*color)) },
            Overlay::CurvePoint { p, color, filled, size } => OverlayItem { filled: *filled, size: *size, ..item("curvePoint", vec![p.x, p.y], rgb(*color)) },
            Overlay::Handle { p, color } => item("handle", vec![p.x, p.y], rgb(*color)),
            Overlay::Label { p, text, color } => OverlayItem { text: text.clone(), ..item("label", vec![p.x, p.y], rgb(*color)) },
            Overlay::Measure { p, text } => OverlayItem { text: text.clone(), ..item("measure", vec![p.x, p.y], [90, 90, 90, 255]) },
            Overlay::Highlight { quad, color } => {
                OverlayItem { filled: true, ..item("highlight", quad.iter().flat_map(|q| [q.x, q.y]).collect(), *color) }
            }
            Overlay::Swatch { p, color, selected } => OverlayItem { filled: *selected, ..item("swatch", vec![p.x, p.y], *color) },
            Overlay::GridLine { a, b, color } => item("gridLine", vec![a.x, a.y, b.x, b.y], *color),
        })
        .collect()
}

// ---------------------------------------------------------------------------------------------
// Free functions
// ---------------------------------------------------------------------------------------------

/// Every engine command with its menu placement, shortcut and params doc.
#[uniffi::export]
pub fn command_catalog() -> Vec<CommandInfo> {
    vectorcraft_engine::command_specs()
        .iter()
        .map(|c| CommandInfo {
            id: c.id.to_string(),
            label: c.label.to_string(),
            menu: c.menu.iter().map(|m| (*m).to_string()).collect(),
            shortcut: c.shortcut.map(str::to_string),
            params: c.params.to_string(),
            is_query: !c.journal,
        })
        .collect()
}

/// UI-only desktop commands (views, panels, tools, dialogs).
#[uniffi::export]
pub fn ui_command_catalog() -> Vec<UiCommandInfo> {
    catch_unwind(menus_src::ui_commands).unwrap_or_default()
}

/// The desktop menu bar layout.
#[uniffi::export]
pub fn desktop_menu_layout() -> Vec<MenuSection> {
    catch_unwind(menus_src::menu_layout).unwrap_or_default()
}

/// Parsed parameters of a command (empty for unknown ids and commands without params).
#[uniffi::export]
pub fn command_params(id: String) -> Vec<ParamField> {
    catch_unwind(|| params_doc::fields_for(&id)).unwrap_or_default()
}

/// `None` = supported on iOS; `Some(reason)` from `ios-excluded-commands.txt`.
#[uniffi::export]
pub fn command_platform_support(id: String) -> Option<String> {
    params_doc::excluded_commands().into_iter().find(|(e, _)| *e == id).map(|(_, reason)| reason)
}

/// The toolbar groups, in desktop order.
#[uniffi::export]
pub fn tool_catalog() -> Vec<ToolGroupInfo> {
    vectorcraft_tools::TOOL_GROUPS
        .iter()
        .map(|g| ToolGroupInfo {
            tools: g
                .iter()
                .map(|t| ToolInfo { id: t.id.to_string(), label: t.label.to_string(), shortcut: t.shortcut.map(str::to_string), icon: t.icon.to_string() })
                .collect(),
        })
        .collect()
}

/// The Window menu's panel entries, in menu order.
#[uniffi::export]
pub fn panel_catalog() -> Vec<PanelInfo> {
    catch_unwind(|| menus_src::panel_catalog(&menus_src::menu_layout())).unwrap_or_default()
}

#[uniffi::export]
pub fn engine_version() -> String {
    format!("vectorcraft-apple {}", env!("CARGO_PKG_VERSION"))
}

/// iOS has no font folders the engine knows (fontdb's non-macOS branch lists Linux paths): add
/// `/System/Library/Fonts` and the app's own font folder as user font dirs, then start the background
/// scan. Idempotent.
#[uniffi::export]
pub fn configure_fonts(app_font_dir: Option<String>) {
    static ONCE: std::sync::Once = std::sync::Once::new();
    let _ = catch_unwind(|| {
        ONCE.call_once(|| {
            let mut dirs: Vec<PathBuf> = vec![PathBuf::from("/System/Library/Fonts")];
            if let Some(d) = app_font_dir.filter(|d| !d.is_empty()) {
                let p = PathBuf::from(d);
                // Created now so a font copied in later is found by the next scan.
                let _ = std::fs::create_dir_all(&p);
                vectorcraft_text::set_app_font_dir(p.clone());
                dirs.push(p);
            }
            vectorcraft_text::set_user_font_dirs(dirs);
            vectorcraft_text::FontDb::global().scan_in_background();
        });
    });
}
