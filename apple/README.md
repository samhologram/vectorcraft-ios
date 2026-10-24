# VectorCraft for iPad and iPhone

Native SwiftUI app on the unchanged VectorCraft Rust engine (UniFFI bridge in `bridge/`). Fork rules: `../FORK.md`.
Contracts between the bridge, the Swift core and the UI: `docs/CONTRACT.md`. Recipe followed:
`/Users/samuelhalle/Code/CraftApps/COOKBOOK.md` (revision 2).

## UX direction

Apple's Human Interface Guidelines first (system components, Liquid Glass materials, Dynamic Type, keyboard and
pointer, Apple Pencil, dark and light). Faithful to the desktop app's mental model: the same tools (Selection, Direct
Selection, Pen, Curvature, Type, Shapes, Pencil, Paintbrush, Eraser, Rotate, Scale, Gradient, Eyedropper…) in the same
toolbar groups, the same panels (Properties, Layers, Color, Swatches, Stroke, Transparency, Appearance, Align,
Pathfinder, Transform, Artboards, Character, Paragraph, History…) and the same menu structure (File, Edit, Object,
Type, Select, Effect, View, Window, Help).

**Reference app: Linearity Curve (formerly Vectornator)**, the most visible, best-reviewed vector design app built for
iPad and iPhone on the App Store (checked 2026-10-23); **Affinity Designer for iPad** as the secondary reference for
the pro-tool layout. Behaviour and look only, clean-room: no assets, icons or code from either; icons are SF Symbols.
VectorCraft's own clean-room rule (no Adobe software, assets or wording) applies to this fork too.

Conventions taken from it:

1. **Document browser first.** The system document browser (Files) opens and creates `.vectorcraft` documents; SVG,
   PDF and the legacy `.drawcraft` open too (imported into a new VectorCraft document on save).
2. **iPad: vertical tool palette on the leading edge**, one button per tool group showing the group's current tool;
   long-press (or a second tap) opens a flyout with the group's other tools.
3. **iPad: inspector on the trailing edge** with a panel switcher (Properties first, then Layers, Color, Stroke…).
   Properties is contextual: it shows what applies to the selection (fill, stroke, opacity, transform, align).
4. **Context bar for the active tool** above the canvas (tool options: corner radius, sides, brush size…) and the
   selection's quick actions (group, arrange, boolean operations).
5. **Canvas gestures**: one finger or Pencil draws/acts with the tool; two-finger pinch zooms, two-finger drag pans,
   two-finger tap undoes, three-finger tap redoes; double-tap with two fingers fits the artboard.
6. **Apple Pencil**: pressure feeds the tool (Paintbrush, Blob Brush, Pencil, Width); with "Only Draw with Apple
   Pencil" a finger pans instead of drawing; double-tap on the Pencil toggles the last two tools.
7. **iPhone: bottom tool strip** that scrolls horizontally (one button per group), and panels in sheets with
   medium/large detents that keep the canvas visible above them.
8. **Top bar**: back to documents (title, rename), undo / redo, the Window panels menu, share/export, and a "…"
   overflow with the full desktop menu bar (File, Edit, Object, Type, Select, Effect, View, Window, Help).
9. **Colour wells** for fill and stroke in the inspector and the context bar; tapping one opens the Color panel
   (swatches and the system colour picker).
10. **Layers list** with thumbnails-free rows, eye and lock toggles, drag to reorder, swipe to delete.

Per-idiom degradation (iPad windows are resizable, in either orientation, Split View, Stage Manager): full layout
(tool palette + canvas + inspector) → inspector as a sheet when the window is narrower than 700 pt → iPhone layout
(tool strip + sheets) in compact width. Nothing falls off screen: tool palettes scroll as the last resort, labels never
wrap mid-word.

## Build

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer PATH="$HOME/.cargo/bin:$PATH"
apple/scripts/build-xcframework.sh --sim-only --debug
cd apple && xcodegen generate
xcodebuild build-for-testing -scheme VectorCraft -destination 'generic/platform=iOS Simulator' ARCHS=arm64 CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd
```

Gates before every commit: `cd apple/bridge && cargo test && cargo clippy --all-targets -- -D warnings`,
`apple/scripts/check-command-ids.sh`, `apple/scripts/tool-coverage.sh`, `apple/scripts/feature-coverage.sh --check`.

Demo: launch with `-VectorCraftDemo` — a new document is seeded through engine commands (shapes, a star, a gradient,
type) so screenshots and UI tests start from real art.

## App icon

`VectorCraft/Resources/Assets.xcassets/AppIcon.appiconset` and `LaunchIcon.imageset` are upstream
`assets/app-icon/vectorcraft.svg` rendered full-bleed (rounded clip removed), opaque, 1024 px (licence:
`docs/APP-ICON-LICENSE.txt`, copied from `assets/app-icon/LICENSE.txt`).

## Panels (cookbook §4, 2026-10-24)

Every desktop panel opens from the inspector's panel menu and the Window menu; on iPad panels stack in the inspector
and can be added, hidden, collapsed and reordered (arrangement persisted); on iPhone each panel is a sheet. Panel-owned
actions (new layer, new swatch…) live in the panel's header. Spec and current gaps: `docs/CONTRACT.md` §6.

## Productivity (cookbook §0b, 2026-10-24)

Hyper-productive, Apple-clean: every frequent action ≤ 1 tap from the canvas, every desktop shortcut on a hardware
keyboard (⌘K palette), context menus and drag & drop everywhere, Pencil double-tap/squeeze/hover, scrubbable fields,
customizable toolbar, remembered tool/layout/values, multi-window; system components only, one primary action per
area. Spec and current gaps: `docs/CONTRACT.md` §7.

## Device media (cookbook §0b, 2026-10-24)

Start a document from, or place into the current one, images/SVG/PDF from Photos, Files/iCloud, drag & drop and paste.
Spec and gaps: `docs/CONTRACT.md` §8.
