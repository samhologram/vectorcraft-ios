//! Read-only views of the session: state, selection, layer rows.

use crate::{ArtboardInfo, DocState, Inner, LayerRow, RectInfo, SelectionInfo};
use vectorcraft_doc::{Node, NodeId};
use vectorcraft_engine::Session;
use vectorcraft_engine::inspect::{SummaryOpts, node_summary_opts};

fn rect(r: kurbo::Rect) -> RectInfo {
    RectInfo { x: r.x0, y: r.y0, width: r.width(), height: r.height() }
}

pub(crate) fn paint_label(p: &vectorcraft_color::Paint) -> String {
    match p {
        vectorcraft_color::Paint::None => "none".into(),
        vectorcraft_color::Paint::Solid { color, .. } => color.to_hex(),
        vectorcraft_color::Paint::Gradient(_) => "gradient".into(),
        vectorcraft_color::Paint::Pattern { .. } => "pattern".into(),
    }
}

pub(crate) fn doc_state(i: &Inner) -> DocState {
    let s = &i.session;
    let (title, dirty, artboards, can_undo, can_redo, undo_label, redo_label, color_mode) = match s.active() {
        Some(d) => (
            d.title(),
            d.is_dirty(),
            d.doc.artboards.iter().enumerate().map(|(n, a)| ArtboardInfo { index: u32::try_from(n).unwrap_or(u32::MAX), name: a.name.clone(), rect: rect(a.rect) }).collect(),
            !d.history.undo.is_empty(),
            !d.history.redo.is_empty(),
            d.history.undo.last().map(|e| e.label.clone()),
            d.history.redo.last().map(|e| e.label.clone()),
            match d.doc.color_mode {
                vectorcraft_doc::ColorMode::Rgb => "rgb",
                vectorcraft_doc::ColorMode::Cmyk => "cmyk",
            },
        ),
        None => (String::new(), false, Vec::new(), false, false, None, None, "rgb"),
    };
    DocState {
        title,
        dirty,
        active_artboard: i.artboard.min(u32::try_from(artboards.len().saturating_sub(1)).unwrap_or(0)),
        artboards,
        tool: s.tool_id().to_string(),
        tool_wants_text: s.tool_wants_text(),
        in_interaction: s.in_interaction(),
        can_undo,
        can_redo,
        undo_label,
        redo_label,
        revision: i.revision,
        history_id: i.history_id,
        color_mode: color_mode.into(),
        fill_default: paint_label(&s.paint.fill),
        stroke_default: paint_label(&s.paint.stroke),
    }
}

pub(crate) fn empty_selection() -> SelectionInfo {
    SelectionInfo { count: 0, ids: Vec::new(), bounds: None, fill: None, stroke: None, stroke_width: None, opacity: None, kinds: Vec::new() }
}

/// Normalise an inspect paint label (`#rrggbb`, `None`, `Name (#rrggbb)`, `Linear gradient`, `pattern x`).
fn norm_paint(label: &str) -> String {
    let l = label.trim();
    if l.eq_ignore_ascii_case("none") {
        "none".into()
    } else if l.starts_with('#') {
        l.to_ascii_lowercase()
    } else if l.to_ascii_lowercase().contains("gradient") {
        "gradient".into()
    } else if l.to_ascii_lowercase().starts_with("pattern") {
        "pattern".into()
    } else if let (Some(a), Some(b)) = (l.rfind("(#"), l.rfind(')')) {
        l.get(a + 1..b).unwrap_or(l).to_ascii_lowercase()
    } else {
        l.to_string()
    }
}

fn merge(slot: &mut Option<String>, v: String) {
    match slot {
        None => *slot = Some(v),
        Some(cur) if *cur != v => *cur = "mixed".into(),
        _ => {}
    }
}

pub(crate) fn selection(s: &Session) -> SelectionInfo {
    let Some(st) = s.active() else { return empty_selection() };
    let ids: Vec<NodeId> = st.selection.objects.clone();
    if ids.is_empty() {
        return empty_selection();
    }
    let symbols = st.doc.symbol_boxes();
    let (mut fill, mut stroke): (Option<String>, Option<String>) = (None, None);
    let (mut width, mut opacity): (Option<f64>, Option<f64>) = (None, None);
    let mut kinds: Vec<String> = Vec::new();
    for id in &ids {
        let Some(n) = st.doc.node(*id) else { continue };
        let k = n.kind_label().to_string();
        if !kinds.contains(&k) {
            kinds.push(k);
        }
        opacity = Some(match opacity {
            Some(o) => o.min(f64::from(n.opacity)),
            None => f64::from(n.opacity),
        });
        let v = node_summary_opts(n, SummaryOpts { depth: Some(0), child_limit: Some(0), compound_member: false }, &symbols);
        if let Some(f) = v.get("fill").and_then(|x| x.as_str()) {
            merge(&mut fill, norm_paint(f));
        }
        if let Some(f) = v.get("stroke").and_then(|x| x.as_str()) {
            merge(&mut stroke, norm_paint(f));
        }
        if let Some(w) = v.get("strokeWidth").and_then(|x| x.as_f64()) {
            width = Some(width.map_or(w, |c| c.max(w)));
        }
    }
    SelectionInfo {
        count: u32::try_from(ids.len()).unwrap_or(u32::MAX),
        ids: ids.iter().map(|i| i.0).collect(),
        bounds: st.doc.bounds_of(&ids, false).map(rect),
        fill: Some(fill.unwrap_or_else(|| "none".into())),
        stroke: Some(stroke.unwrap_or_else(|| "none".into())),
        stroke_width: Some(width.unwrap_or(0.0)),
        opacity,
        kinds,
    }
}

const MAX_DEPTH: u32 = 64;

/// The layer tree flattened depth-first, the top of the stack first, capped at `max`.
pub(crate) fn layers(s: &Session, max: usize) -> Vec<LayerRow> {
    let Some(st) = s.active() else { return Vec::new() };
    let selected: std::collections::HashSet<NodeId> = st.selection.objects.iter().copied().collect();
    fn walk(n: &Node, parent: Option<u64>, depth: u32, sel: &std::collections::HashSet<NodeId>, max: usize, out: &mut Vec<LayerRow>) {
        if out.len() >= max {
            return;
        }
        let kids = n.children();
        out.push(LayerRow {
            id: n.id.0,
            name: n.display_name(),
            kind: n.kind_label().to_string(),
            depth,
            parent,
            visible: n.visible,
            locked: n.locked,
            selected: sel.contains(&n.id),
            has_children: kids.is_some_and(|k| !k.is_empty()),
        });
        if depth < MAX_DEPTH
            && let Some(kids) = kids
        {
            for c in kids.iter().rev() {
                walk(c, Some(n.id.0), depth + 1, sel, max, out);
            }
        }
    }
    let mut out = Vec::new();
    for l in st.doc.layers.iter().rev() {
        walk(l, None, 0, &selected, max, &mut out);
    }
    out
}
