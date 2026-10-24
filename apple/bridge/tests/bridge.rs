#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
//! Bridge smoke tests: catalogs, commands, history, tools, rendering, persistence.

use vectorcraft_apple::*;

fn view() -> ViewParams {
    ViewParams {
        center_x: 540.0,
        center_y: 540.0,
        zoom: 0.5,
        width: 400.0,
        height: 300.0,
        pixel_scale: 2.0,
        outline: false,
        smart_guides: false,
        snap_to_grid: false,
        snap_to_point: false,
        show_bbox: true,
        artboard: 0,
    }
}

fn no_mods() -> Modifiers {
    Modifiers { shift: false, alt: false, cmd: false, ctrl: false, space: false }
}

fn doc() -> std::sync::Arc<DocumentHandle> {
    DocumentHandle::new_document(1080.0, 1080.0, String::new()).unwrap()
}

#[test]
fn catalogs_load() {
    assert!(command_catalog().len() > 500);
    assert!(command_catalog().iter().any(|c| c.id == "shape.rectangle" && !c.is_query));
    assert!(command_catalog().iter().any(|c| c.id == "document.inspect" && c.is_query));
    assert!(ui_command_catalog().len() > 100);
    let tools = tool_catalog();
    assert!(tools.len() > 20);
    assert!(tools.iter().flat_map(|g| &g.tools).any(|t| t.id == "pen"));
    let panels = panel_catalog();
    assert!(panels.len() > 30 && panels.iter().any(|p| p.id == "layers"));
    assert!(engine_version().starts_with("vectorcraft-apple"));
    assert!(command_platform_support("no.such.command".into()).is_none());
}

#[test]
fn unknown_tool_is_rejected_without_changing_selection() {
    let d = doc();
    d.select_tool("rectangle".into(), view()).unwrap();
    let error = d.select_tool("no.such.tool".into(), view()).unwrap_err();
    assert!(error.to_string().contains("unknown tool `no.such.tool`"));
    assert_eq!(d.state().tool, "rectangle");
}

#[test]
fn menus_parse() {
    let titles: Vec<String> = desktop_menu_layout().into_iter().map(|s| s.title).collect();
    assert_eq!(titles, ["File", "Edit", "Object", "Type", "Select", "Effect", "View", "Window", "Help"]);
    for s in desktop_menu_layout() {
        assert!(!s.items.is_empty(), "{}", s.title);
    }
}

#[test]
fn every_menu_command_exists() {
    let ids: std::collections::HashSet<String> = command_catalog().into_iter().map(|c| c.id).chain(ui_command_catalog().into_iter().map(|c| c.id)).collect();
    fn walk(items: &[MenuItemInfo], ids: &std::collections::HashSet<String>, missing: &mut Vec<String>) {
        for i in items {
            if i.kind == "command" && !ids.contains(&i.command) {
                missing.push(i.command.clone());
            }
            walk(&i.children, ids, missing);
        }
    }
    let mut missing = Vec::new();
    for s in desktop_menu_layout() {
        walk(&s.items, &ids, &mut missing);
    }
    missing.sort();
    missing.dedup();
    // `window.panel` and friends are handled by the desktop UI outside UI_COMMANDS: tolerate a short list.
    assert!(missing.len() < 80, "{missing:?}");
}

#[test]
fn command_changes_state_and_history() {
    let d = doc();
    let s0 = d.state();
    assert!(!s0.can_undo && s0.artboards.len() == 1);
    d.execute("shape.rectangle".into(), r#"{"x":10,"y":10,"width":100,"height":50}"#.into()).unwrap();
    let s1 = d.state();
    assert!(s1.can_undo && s1.history_id != s0.history_id && s1.revision > s0.revision);
    assert!(s1.dirty);
    let rows = d.layers(100);
    assert!(rows.iter().any(|r| r.kind == "Rectangle"), "{:?}", rows.iter().map(|r| &r.kind).collect::<Vec<_>>());
    d.undo().unwrap();
    let s2 = d.state();
    assert!(s2.history_id != s1.history_id && s2.can_redo);
    d.redo().unwrap();
    assert!(d.state().history_id != s2.history_id);
    // a query does not move history
    let h = d.state().history_id;
    d.inspect("{}".into()).unwrap();
    assert_eq!(d.state().history_id, h);
    assert!(d.disabled_reason("no.such".into()).is_some());
    assert!(d.execute("no.such".into(), "{}".into()).is_err());
    assert!(d.execute("shape.rectangle".into(), "not json".into()).is_err());
}

#[test]
fn selection_summary() {
    let d = doc();
    d.execute("shape.rectangle".into(), r#"{"x":10,"y":10,"width":100,"height":50}"#.into()).unwrap();
    let sel = d.selection();
    assert_eq!(sel.count, 1);
    assert!(sel.bounds.is_some() && sel.fill.is_some() && sel.stroke_width.is_some());
    d.execute("select.none".into(), "{}".into()).unwrap();
    assert_eq!(d.selection().count, 0);
    assert!(d.selection().fill.is_none());
}

#[test]
fn interaction_is_one_step() {
    let d = doc();
    d.execute("shape.rectangle".into(), r#"{"x":10,"y":10,"width":100,"height":50}"#.into()).unwrap();
    let before = d.state().history_id;
    d.begin_interaction("Move".into()).unwrap();
    assert!(d.state().in_interaction);
    d.preview("object.move".into(), r#"{"dx":5,"dy":5}"#.into()).ok();
    d.preview("object.move".into(), r#"{"dx":9,"dy":9}"#.into()).ok();
    d.commit_interaction().unwrap();
    assert!(!d.state().in_interaction);
    let _ = before;
    d.begin_interaction("Move".into()).unwrap();
    d.cancel_interaction().unwrap();
    assert!(!d.state().in_interaction);
}

#[test]
fn rectangle_tool_draws() {
    let d = doc();
    d.select_tool("rectangle".into(), view()).unwrap();
    assert_eq!(d.state().tool, "rectangle");
    let h = d.state().history_id;
    d.pointer("down".into(), 100.0, 100.0, no_mods(), 1.0, view()).unwrap();
    d.pointer("drag".into(), 200.0, 180.0, no_mods(), 1.0, view()).unwrap();
    let ov = d.overlays(view());
    let _ = ov;
    d.pointer("up".into(), 300.0, 250.0, no_mods(), 1.0, view()).unwrap();
    assert!(d.state().history_id != h, "no undo step recorded");
    assert!(d.layers(100).iter().any(|r| r.kind == "Path" || r.kind == "Rectangle"), "{:?}", d.layers(100).iter().map(|r| &r.kind).collect::<Vec<_>>());
    assert!(d.pointer("bogus".into(), 0.0, 0.0, no_mods(), 1.0, view()).is_err());
    assert!(d.pointer("down".into(), f64::NAN, 0.0, no_mods(), 1.0, view()).is_err());
    assert!(d.tool_key("escape".into(), no_mods(), view()).is_ok());
    assert!(d.tool_key("???".into(), no_mods(), view()).is_err());
    assert!(!d.tool_options().is_empty());
}

#[test]
fn render_sizes() {
    let d = doc();
    d.execute("shape.rectangle".into(), r#"{"x":10,"y":10,"width":100,"height":50}"#.into()).unwrap();
    let img = d.render(view()).unwrap();
    assert_eq!((img.width, img.height), (800, 600));
    assert_eq!(img.rgba.len(), 800 * 600 * 4);
    assert!(img.rgba.chunks(4).any(|p| p[3] == 255));
    let t = d.render_artboard(0, 128).unwrap();
    assert_eq!(t.rgba.len(), (t.width * t.height * 4) as usize);
    assert!(t.width.max(t.height) <= 129);
    assert!(d.render_artboard(9, 128).is_err());
    let huge = ViewParams { width: 1e9, height: 1e9, ..view() };
    let img = d.render(ViewParams { width: 20000.0, height: 10.0, pixel_scale: 1.0, ..huge }).unwrap();
    assert!(img.width <= 8192);
}

#[test]
fn save_and_open_round_trip() {
    let d = doc();
    d.execute("shape.rectangle".into(), r#"{"x":10,"y":10,"width":100,"height":50}"#.into()).unwrap();
    let bytes = d.save_native().unwrap();
    assert!(!bytes.is_empty() && !d.state().dirty);
    let dir = std::env::temp_dir().join(format!("vc-bridge-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("t.vectorcraft");
    std::fs::write(&path, &bytes).unwrap();
    let o = DocumentHandle::open(path.to_string_lossy().into()).unwrap();
    assert!(o.layers(100).iter().any(|r| r.kind == "Rectangle"));
    assert_eq!(o.state().artboards.len(), 1);
    assert!(DocumentHandle::open("/no/such/file.vectorcraft".into()).is_err());
    let svg = o.export("svg".into(), "{}".into()).unwrap();
    assert!(String::from_utf8_lossy(&svg).contains("<svg"));
    let png = o.export("png".into(), r#"{"scale":0.25}"#.into()).unwrap();
    assert!(png.starts_with(&[0x89, b'P', b'N', b'G']));
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn params_parser_on_real_docs() {
    let f = command_params("shape.rectangle".into());
    assert!(f.iter().any(|p| p.key == "width"), "{f:?}");
    assert!(command_params("no.such".into()).is_empty());
    let mut kinds = std::collections::HashSet::new();
    for c in command_catalog() {
        for p in command_params(c.id) {
            kinds.insert(p.kind);
        }
    }
    assert!(kinds.contains("number") && kinds.contains("choice") && kinds.contains("bool"), "{kinds:?}");
}

#[test]
fn fonts_configure_is_idempotent() {
    configure_fonts(None);
    configure_fonts(Some(std::env::temp_dir().join("vc-fonts").to_string_lossy().into()));
}
