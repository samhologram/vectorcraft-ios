//! The Effect menu. On desktop it is built at run time from `vectorcraft_effects::effect_catalog()` (not a
//! static table in `menus.rs`), so the bridge builds it the same way, from the same catalogue, without egui.
//! Mirrors `effect_menu()` in `crates/ui-egui/src/menus.rs`; plug-in effects are left out (no plug-ins on iOS).

use crate::MenuItemInfo;
use serde_json::json;
use vectorcraft_effects::EffectInfo;

const ORDER: [&str; 11] = [
    "3D and Materials",
    "Color Adjustments",
    "Convert to Shape",
    "Crop Marks",
    "Distort & Transform",
    "Path",
    "Pathfinder",
    "Rasterize…",
    "Stylize",
    "SVG Filters",
    "Warp",
];

const RASTER_MENUS: [&str; 10] = ["Artistic", "Blur", "Brush Strokes", "Distort", "Pixelate", "Sharpen", "Sketch", "Stylize", "Texture", "Video"];

fn cmd(label: &str, command: &str, params: serde_json::Value) -> MenuItemInfo {
    MenuItemInfo { kind: "command".into(), label: label.into(), command: command.into(), params_json: params.to_string(), children: vec![] }
}
fn plain(label: &str, command: &str) -> MenuItemInfo {
    cmd(label, command, json!({}))
}
fn todo(label: &str) -> MenuItemInfo {
    MenuItemInfo { kind: "todo".into(), label: label.into(), command: String::new(), params_json: "{}".into(), children: vec![] }
}
fn sep() -> MenuItemInfo {
    MenuItemInfo { kind: "separator".into(), label: String::new(), command: String::new(), params_json: "{}".into(), children: vec![] }
}
fn submenu(label: &str, children: Vec<MenuItemInfo>) -> MenuItemInfo {
    MenuItemInfo { kind: "submenu".into(), label: label.into(), command: String::new(), params_json: "{}".into(), children }
}

fn item(e: &EffectInfo) -> MenuItemInfo {
    let no_options = e.defaults.as_object().is_some_and(serde_json::Map::is_empty);
    cmd(e.label, if no_options { "effect.apply" } else { "effect.dialog" }, json!({ "effect": e.id }))
}

pub(crate) fn effect_menu() -> Vec<MenuItemInfo> {
    let cat = vectorcraft_effects::effect_catalog();
    let mut out = vec![
        plain("Apply Last Effect", "effect.applyLast"),
        plain("Last Effect…", "effect.last"),
        sep(),
        plain("Document Raster Effects Settings…", "document.rasterEffectsSettings"),
        sep(),
    ];
    let top_level = |e: &EffectInfo| e.menu == ["Effect"] && ORDER.contains(&e.label);
    let in_vector_menu = |e: &EffectInfo| ORDER.iter().any(|s| e.menu == ["Effect", *s]) && !vectorcraft_effects::PIXEL_EFFECTS.contains(&e.id);
    let items_at = |path: &[&str], vector: bool| -> Vec<MenuItemInfo> { cat.iter().filter(|e| e.menu == path && in_vector_menu(e) == vector).map(item).collect() };
    for name in ORDER {
        if let Some(e) = cat.iter().find(|e| top_level(e) && e.label == name) {
            out.push(item(e));
            continue;
        }
        let mut items = items_at(&["Effect", name], true);
        if items.is_empty() {
            match name {
                "3D and Materials" => out.push(submenu(name, ["Extrude & Bevel…", "Revolve…", "Inflate…", "Rotate…", "Materials…"].into_iter().map(todo).collect())),
                "SVG Filters" => out.push(submenu(name, vec![todo("Apply SVG Filter…")])),
                _ => {}
            }
            continue;
        }
        if name == "3D and Materials" {
            let rank = |label: &str| ["Extrude & Bevel…", "Revolve…", "Inflate…", "Rotate…"].iter().position(|l| *l == label).unwrap_or(9);
            items.sort_by_key(|i| rank(&i.label));
            items.push(todo("Materials…"));
        }
        out.push(submenu(name, items));
    }
    let raster: Vec<MenuItemInfo> = RASTER_MENUS
        .iter()
        .filter_map(|name| {
            let items = items_at(&["Effect", name], false);
            (!items.is_empty()).then(|| submenu(name, items))
        })
        .collect();
    if !raster.is_empty() {
        out.push(sep());
        out.push(plain("Effect Gallery…", "ui.effectGalleryDialog"));
        out.extend(raster);
    }
    let placed = |e: &EffectInfo| top_level(e) || in_vector_menu(e) || RASTER_MENUS.iter().any(|n| e.menu == ["Effect", *n]);
    for e in cat.iter().filter(|e| !placed(e)) {
        out.push(cmd(e.label, "effect.dialog", json!({ "effect": e.id })));
    }
    out
}
