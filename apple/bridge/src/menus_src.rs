//! Parsers for the desktop UI's command table and menu layout, read from upstream source text
//! (`crates/ui-egui/src/menus.rs` and a few panel files) embedded with `include_str!`. No egui dependency.
//!
//! Robust by construction: every access is bounds-checked, malformed input yields fewer entries, and
//! dynamic constructs (iterators over runtime tables, recent-file lists, workspaces) are skipped, never guessed.

use crate::{MenuItemInfo, MenuSection, PanelInfo, UiCommandInfo};
use serde_json::{Value, json};

const MENUS_RS: &str = include_str!("../../../crates/ui-egui/src/menus.rs");
const PANEL_FILES: &[(&str, &str)] = &[
    ("asset_export", include_str!("../../../crates/ui-egui/src/panels/asset_export.rs")),
    ("blend", include_str!("../../../crates/ui-egui/src/panels/blend.rs")),
    ("css_properties", include_str!("../../../crates/ui-egui/src/panels/css_properties.rs")),
    ("flattener_preview", include_str!("../../../crates/ui-egui/src/panels/flattener_preview.rs")),
    ("links", include_str!("../../../crates/ui-egui/src/panels/links.rs")),
    ("svg_interactivity", include_str!("../../../crates/ui-egui/src/panels/svg_interactivity.rs")),
    ("variables", include_str!("../../../crates/ui-egui/src/panels/variables.rs")),
];

#[derive(Debug, PartialEq, Clone)]
enum Tok {
    Str(String),
    Sym(char),
    Word(String),
}

/// A token and its byte range in the source.
#[derive(Debug, Clone)]
struct Sp {
    tok: Tok,
    start: usize,
}

/// Tokenize Rust source: string literals (simple escapes), single punctuation chars and words. Comments
/// are dropped; char literals and lifetimes become punctuation.
fn tokenize(src: &str) -> Vec<Sp> {
    let c: Vec<(usize, char)> = src.char_indices().collect();
    let at = |i: usize| c.get(i).map(|x| x.1);
    let pos = |i: usize| c.get(i).map_or(src.len(), |x| x.0);
    let mut out = Vec::new();
    let mut i = 0;
    while let Some(ch) = at(i) {
        let start = pos(i);
        if ch == '/' && at(i + 1) == Some('/') {
            while at(i).is_some_and(|x| x != '\n') {
                i += 1;
            }
        } else if ch == '/' && at(i + 1) == Some('*') {
            i += 2;
            while i < c.len() && !(at(i) == Some('*') && at(i + 1) == Some('/')) {
                i += 1;
            }
            i += 2;
        } else if ch == 'r' && matches!(at(i + 1), Some('"' | '#')) && raw_string_end(&c, i).is_some() {
            // r"..." / r#"..."# raw strings
            let (s, next) = raw_string_end(&c, i).unwrap_or((String::new(), i + 1));
            i = next;
            out.push(Sp { tok: Tok::Str(s), start });
        } else if ch == '"' {
            let mut s = String::new();
            i += 1;
            while let Some(x) = at(i) {
                if x == '"' {
                    break;
                }
                if x == '\\' {
                    i += 1;
                    match at(i) {
                        Some('n') => s.push('\n'),
                        Some('t') => s.push('\t'),
                        // a line continuation swallows the newline and the next line's indent
                        Some('\n') => {
                            while at(i + 1).is_some_and(char::is_whitespace) {
                                i += 1;
                            }
                        }
                        Some(o) => s.push(o),
                        None => break,
                    }
                } else {
                    s.push(x);
                }
                i += 1;
            }
            i += 1;
            out.push(Sp { tok: Tok::Str(s), start });
        } else if ch.is_alphanumeric() || ch == '_' {
            let mut w = String::new();
            while let Some(x) = at(i) {
                if x.is_alphanumeric() || x == '_' {
                    w.push(x);
                    i += 1;
                } else {
                    break;
                }
            }
            out.push(Sp { tok: Tok::Word(w), start });
        } else {
            i += 1;
            if !ch.is_whitespace() {
                out.push(Sp { tok: Tok::Sym(ch), start });
            }
        }
    }
    out
}

fn raw_string_end(c: &[(usize, char)], i: usize) -> Option<(String, usize)> {
    let mut j = i + 1;
    let mut hashes = 0;
    while c.get(j).map(|x| x.1) == Some('#') {
        hashes += 1;
        j += 1;
    }
    if c.get(j).map(|x| x.1) != Some('"') {
        return None;
    }
    j += 1;
    let mut s = String::new();
    while let Some(&(_, x)) = c.get(j) {
        if x == '"' && (0..hashes).all(|k| c.get(j + 1 + k).map(|y| y.1) == Some('#')) {
            return Some((s, j + 1 + hashes));
        }
        s.push(x);
        j += 1;
    }
    None
}

fn is_sym(t: Option<&Sp>, c: char) -> bool {
    matches!(t, Some(Sp { tok: Tok::Sym(x), .. }) if *x == c)
}
fn word(t: Option<&Sp>) -> Option<&str> {
    match t {
        Some(Sp { tok: Tok::Word(w), .. }) => Some(w),
        _ => None,
    }
}
fn string(t: Option<&Sp>) -> Option<&str> {
    match t {
        Some(Sp { tok: Tok::Str(s), .. }) => Some(s),
        _ => None,
    }
}

/// Index just past the `=` that follows `name` in a `const NAME ... = ` declaration.
fn after_decl(toks: &[Sp], name: &str) -> Option<usize> {
    let mut from = 0;
    while let Some(rel) = toks.get(from..)?.iter().position(|t| matches!(&t.tok, Tok::Word(w) if w == name)) {
        let at = from + rel;
        if at > 0 && word(toks.get(at - 1)) == Some("const") {
            let eq = toks.get(at..)?.iter().position(|t| matches!(t.tok, Tok::Sym('=')))?;
            return Some(at + eq + 1);
        }
        from = at + 1;
    }
    None
}

/// Every UI command declared in `UI_COMMANDS` (entries whose id or label is not a string literal are skipped).
pub fn parse_ui_commands(src: &str) -> Vec<UiCommandInfo> {
    let toks = tokenize(src);
    let Some(start) = after_decl(&toks, "UI_COMMANDS") else { return Vec::new() };
    let mut out = Vec::new();
    let mut depth = 0usize;
    let mut i = start;
    while let Some(t) = toks.get(i) {
        match t.tok {
            Tok::Sym('[') => depth += 1,
            Tok::Sym(']') => {
                depth = depth.saturating_sub(1);
                if depth == 0 {
                    break;
                }
            }
            Tok::Sym(';') if depth == 0 => break,
            Tok::Sym('(') if depth == 1 => {
                if let Some((cmd, next)) = parse_entry(&toks, i) {
                    out.push(cmd);
                    i = next;
                    continue;
                }
            }
            _ => {}
        }
        i += 1;
    }
    out
}

/// `(` Str `,` Str `,` Str `,` Str `)`: id, label, shortcut ("" = none), params doc.
fn parse_entry(toks: &[Sp], open: usize) -> Option<(UiCommandInfo, usize)> {
    let get = |k: usize| toks.get(open + k);
    let id = string(get(1))?;
    let label = string(get(3))?;
    let shortcut = string(get(5))?;
    let params = string(get(7))?;
    if !(is_sym(get(2), ',') && is_sym(get(4), ',') && is_sym(get(6), ',')) {
        return None;
    }
    let close = if is_sym(get(8), ',') { 9 } else { 8 };
    if !is_sym(get(close), ')') {
        return None;
    }
    let shortcut = (!shortcut.is_empty()).then(|| shortcut.to_string());
    Some((UiCommandInfo { id: id.to_string(), label: label.to_string(), shortcut, params: params.to_string() }, open + close + 1))
}

// ---------------------------------------------------------------------------------------------
// Menu layout
// ---------------------------------------------------------------------------------------------

/// Top-level comma-separated argument ranges after the opener at `open`, and the index of its closer.
fn split_args(toks: &[Sp], open: usize) -> (Vec<(usize, usize)>, usize) {
    let mut args = Vec::new();
    let mut depth = 0usize;
    let mut start = open + 1;
    let mut i = open + 1;
    while let Some(t) = toks.get(i) {
        match t.tok {
            Tok::Sym('(' | '[' | '{') => depth += 1,
            Tok::Sym(')' | ']' | '}') => {
                if depth == 0 {
                    if i > start {
                        args.push((start, i));
                    }
                    return (args, i);
                }
                depth -= 1;
            }
            Tok::Sym(',') if depth == 0 => {
                if i > start {
                    args.push((start, i));
                }
                start = i + 1;
            }
            _ => {}
        }
        i += 1;
    }
    (args, toks.len())
}

/// Index of the first `vec ! [` at or after `from` and before `to`, returned as the index of the `[`.
fn first_vec(toks: &[Sp], from: usize, to: usize) -> Option<usize> {
    let to = to.min(toks.len());
    (from..to.saturating_sub(2)).find(|&i| word(toks.get(i)) == Some("vec") && is_sym(toks.get(i + 1), '!') && is_sym(toks.get(i + 2), '[')).map(|i| i + 2)
}

/// `(start, end)` of the body block of `fn name`.
fn fn_body(toks: &[Sp], name: &str) -> Option<(usize, usize)> {
    let at = (0..toks.len()).find(|&i| word(toks.get(i)) == Some("fn") && word(toks.get(i + 1)) == Some(name))?;
    let open = (at..toks.len()).find(|&i| is_sym(toks.get(i), '{'))?;
    let (_, close) = split_args(toks, open);
    Some((open, close))
}

struct Ctx<'a> {
    src: &'a str,
    toks: &'a [Sp],
}

impl Ctx<'_> {
    fn item(kind: &str, label: &str, command: &str, params_json: String, children: Vec<MenuItemInfo>) -> MenuItemInfo {
        MenuItemInfo { kind: kind.into(), label: label.into(), command: command.into(), params_json, children }
    }

    /// The items of a list expression, or `None` when it is dynamic.
    fn items_of(&self, (a, b): (usize, usize), depth: usize) -> Option<Vec<MenuItemInfo>> {
        if depth > 8 {
            return None;
        }
        let t = self.toks;
        // vec![ ... ]
        if word(t.get(a)) == Some("vec") && is_sym(t.get(a + 1), '!') && is_sym(t.get(a + 2), '[') {
            return Some(self.list(a + 2, depth));
        }
        // a block that builds `let mut v = vec![...]`
        if is_sym(t.get(a), '{') {
            let open = first_vec(t, a, b)?;
            return Some(self.list(open, depth));
        }
        // helper fn() -> Vec<Item>
        if let (Some(name), true, true, true) = (word(t.get(a)), is_sym(t.get(a + 1), '('), is_sym(t.get(a + 2), ')'), a + 3 == b) {
            if name == "effect_menu" {
                return Some(crate::effects_menu::effect_menu());
            }
            let (open, close) = fn_body(t, name)?;
            let v = first_vec(t, open, close)?;
            return Some(self.list(v, depth + 1));
        }
        None
    }

    /// Items of the `vec![` whose `[` is at `open`.
    fn list(&self, open: usize, depth: usize) -> Vec<MenuItemInfo> {
        let (args, _) = split_args(self.toks, open);
        args.into_iter().filter_map(|r| self.entry(r, depth)).collect()
    }

    fn json_arg(&self, (a, b): (usize, usize)) -> String {
        // json ! ( ... )
        let t = self.toks;
        if word(t.get(a)) == Some("json") && is_sym(t.get(a + 1), '!') && is_sym(t.get(a + 2), '(') && b >= a + 4 {
            let from = t.get(a + 3).map(|x| x.start);
            let to = t.get(b - 1).map(|x| x.start);
            if let (Some(f), Some(e)) = (from, to)
                && let Some(text) = self.src.get(f..e)
                && let Ok(v) = serde_json::from_str::<Value>(text.trim())
            {
                return v.to_string();
            }
        }
        "{}".into()
    }

    fn entry(&self, (a, b): (usize, usize), depth: usize) -> Option<MenuItemInfo> {
        let t = self.toks;
        // `Sep` or `Item::Sep`
        if word(t.get(b.checked_sub(1)?)) == Some("Sep") && b - a <= 4 {
            return Some(Self::item("separator", "", "", "{}".into(), vec![]));
        }
        let name = word(t.get(a))?;
        if !is_sym(t.get(a + 1), '(') {
            return None;
        }
        let (args, _) = split_args(t, a + 1);
        let s = |k: usize| args.get(k).and_then(|&(x, y)| if y == x + 1 { string(t.get(x)) } else { None });
        match name {
            "c" => Some(Self::item("command", s(0)?, s(1)?, "{}".into(), vec![])),
            "cp" => Some(Self::item("command", s(0)?, s(1)?, self.json_arg(*args.get(2)?), vec![])),
            "todo" | "todos" => Some(Self::item("todo", s(0)?, "", "{}".into(), vec![])),
            "panel" => {
                let label = s(0)?;
                let &(x, y) = args.get(1)?;
                let id = if y == x + 1 { string(t.get(x))?.to_string() } else { self.panel_path(x, y)? };
                Some(Self::item("command", label, "window.panel", json!({"panel": id, "toggle": true}).to_string(), vec![]))
            }
            "sub" => {
                let children = self.items_of(*args.get(1)?, depth + 1)?;
                Some(Self::item("submenu", s(0)?, "", "{}".into(), children))
            }
            _ => None,
        }
    }

    /// `crate :: panels :: module :: ID` -> the module's `pub const ID`.
    fn panel_path(&self, x: usize, y: usize) -> Option<String> {
        let t = self.toks;
        let module = (x..y).filter_map(|i| word(t.get(i))).rev().nth(1)?;
        let (_, file) = PANEL_FILES.iter().find(|(m, _)| *m == module)?;
        panel_const_id(file)
    }
}

fn panel_const_id(src: &str) -> Option<String> {
    let toks = tokenize(src);
    let at = after_decl(&toks, "ID")?;
    string(toks.get(at)).map(str::to_string)
}

/// The desktop menu bar from `menu_tree_named`'s source: titles in order, "VectorCraft" (the app menu) dropped.
pub fn parse_menu_layout(src: &str) -> Vec<MenuSection> {
    let toks = tokenize(src);
    let Some((open, close)) = fn_body(&toks, "menu_tree_named") else { return Vec::new() };
    let Some(outer) = first_vec(&toks, open, close) else { return Vec::new() };
    let cx = Ctx { src, toks: &toks };
    let (menus, _) = split_args(&toks, outer);
    let mut out = Vec::new();
    for (a, _) in menus {
        if !is_sym(toks.get(a), '(') {
            continue;
        }
        let (parts, _) = split_args(&toks, a);
        let (Some(title), Some(&body)) = (parts.first().and_then(|&(x, _)| string(toks.get(x))), parts.get(1)) else { continue };
        if title == "VectorCraft" {
            continue;
        }
        let items = cx.items_of(body, 0).unwrap_or_default();
        out.push(MenuSection { title: title.to_string(), items });
    }
    out
}

/// UI-only desktop commands, from the embedded upstream source.
pub fn ui_commands() -> Vec<UiCommandInfo> {
    parse_ui_commands(MENUS_RS)
}

/// The desktop menu bar, from the embedded upstream source.
pub fn menu_layout() -> Vec<MenuSection> {
    parse_menu_layout(MENUS_RS)
}

/// The Window menu's `panel(...)` entries in menu order (`["Window"]` or `["Window", "Type"]`).
pub fn panel_catalog(layout: &[MenuSection]) -> Vec<PanelInfo> {
    fn walk(items: &[MenuItemInfo], path: &mut Vec<String>, out: &mut Vec<PanelInfo>) {
        for it in items {
            match it.kind.as_str() {
                "command" if it.command == "window.panel" => {
                    let id = serde_json::from_str::<Value>(&it.params_json).ok().and_then(|v| v.get("panel").and_then(Value::as_str).map(str::to_string));
                    // `Customize…` under View > Proof Setup is a plain open, not a toggle: only toggles are panel entries.
                    let toggle = serde_json::from_str::<Value>(&it.params_json).ok().and_then(|v| v.get("toggle").and_then(Value::as_bool)).unwrap_or(false);
                    if let (Some(id), true) = (id, toggle) {
                        out.push(PanelInfo { id, label: it.label.clone(), menu: path.clone() });
                    }
                }
                "submenu" => {
                    path.push(it.label.clone());
                    walk(&it.children, path, out);
                    path.pop();
                }
                _ => {}
            }
        }
    }
    let mut out = Vec::new();
    for s in layout.iter().filter(|s| s.title == "Window") {
        walk(&s.items, &mut vec!["Window".to_string()], &mut out);
    }
    out
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
mod tests {
    use super::*;

    #[test]
    fn parses_ui_commands() {
        let src = r##"
pub const UI_COMMANDS: &[(&str, &str, &str, &str)] = &[
    // comment ("fake", "x", "", "")
    ("view.a", "A \"q\"", "Cmd+A", "{x} doc"),
    ("view.b", crate::i18n::B, "", ""),
    ("view.c", "C", "", r#"{raw "q"}"#),
];"##;
        let v = parse_ui_commands(src);
        let ids: Vec<&str> = v.iter().map(|c| c.id.as_str()).collect();
        assert_eq!(ids, ["view.a", "view.c"]);
        assert_eq!(v[0].shortcut.as_deref(), Some("Cmd+A"));
        assert_eq!(v[0].label, "A \"q\"");
        assert_eq!(v[1].shortcut, None);
        assert_eq!(v[1].params, "{raw \"q\"}");
    }

    #[test]
    fn parses_menu_layout() {
        let src = r#"
pub fn menu_tree_named(x: bool) -> Vec<(&'static str, Vec<Item>)> {
    let panel = |l, i| cp(l, "window.panel", json!({ "panel": i, "toggle": true }));
    vec![
        ("VectorCraft", vec![c("About", "help.about")]),
        ("File", vec![c("New", "file.new"), Sep, sub("Sub", vec![cp("P", "x.y", json!({"a": 1})), todo("T")]), sub("Dyn", FOO.iter().collect()), helper_call()]),
        ("Edit", { let mut v = vec![c("U", "edit.undo"), Item::Sep]; v.extend(X); v }),
        ("Window", vec![panel("Layers", "layers"), sub("Type", vec![panel("Glyphs", "glyphs"), panel("Links", crate::panels::links::ID)])]),
    ]
}
fn helper() -> Vec<Item> { vec![c("H", "h.h")] }
"#;
        let v = parse_menu_layout(src);
        assert_eq!(v.iter().map(|s| s.title.as_str()).collect::<Vec<_>>(), ["File", "Edit", "Window"]);
        let file = &v[0].items;
        assert_eq!(file.len(), 3, "{file:?}");
        assert_eq!(file[2].kind, "submenu");
        assert_eq!(file[2].children[0].params_json, r#"{"a":1}"#);
        assert_eq!(file[2].children[1].kind, "todo");
        assert_eq!(v[1].items.len(), 2);
        let panels = panel_catalog(&v);
        assert_eq!(panels.iter().map(|p| (p.id.as_str(), p.menu.len())).collect::<Vec<_>>(), [("layers", 1), ("glyphs", 2), ("links", 2)]);
    }

    #[test]
    fn garbage_never_panics() {
        for s in [
            "",
            "\"",
            "/*",
            "r#\"",
            "const UI_COMMANDS = [(",
            "const UI_COMMANDS: X = &[(\"a\",",
            "fn menu_tree_named() { vec![ (\"a\", vec![c(",
            "fn menu_tree_named() { vec![ ( vec![ sub(",
            "\\",
            "fn menu_tree_named() { vec![(\"File\", {",
            "fn menu_tree_named() { vec![(\"File\", f())] } fn f() { f() }",
        ] {
            let _ = parse_ui_commands(s);
            let _ = panel_catalog(&parse_menu_layout(s));
        }
        // every prefix of the real source
        let src: String = MENUS_RS.chars().take(6000).collect();
        for n in (0..src.len()).step_by(997) {
            if let Some(p) = src.get(..n) {
                let _ = parse_ui_commands(p);
                let _ = parse_menu_layout(p);
            }
        }
    }

    #[test]
    fn real_sources() {
        let ui = ui_commands();
        assert!(ui.len() > 100, "{}", ui.len());
        assert!(ui.iter().any(|c| c.id == "view.zoomIn" || c.id == "file.open"));
        let m = menu_layout();
        let titles: Vec<&str> = m.iter().map(|s| s.title.as_str()).collect();
        assert_eq!(titles, ["File", "Edit", "Object", "Type", "Select", "Effect", "View", "Window", "Help"]);
        assert!(m.iter().all(|s| !s.items.is_empty()), "{titles:?}");
        let panels = panel_catalog(&m);
        assert!(panels.len() > 30, "{}", panels.len());
        for id in ["layers", "colorGuide", "links", "variables", "character"] {
            assert!(panels.iter().any(|p| p.id == id), "missing panel {id}");
        }
        assert!(panels.iter().any(|p| p.id == "character" && p.menu == ["Window", "Type"]));
    }
}
