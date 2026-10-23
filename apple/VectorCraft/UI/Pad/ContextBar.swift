import SwiftUI
import VectorCraftKit

/// Bar above the canvas: the active tool's options (`toolOption.<key>`) and the selection's quick actions
/// (group, arrange, align, Pathfinder, delete). Degrades: labels + icons, icons only, then scrolls.
struct ContextBar: View {
    let model: DocumentModel
    var compact = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(labels: true)
            row(labels: false)
            ScrollView(.horizontal) { row(labels: false) }.scrollIndicators(.hidden)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contextBar")
    }

    private func row(labels: Bool) -> some View {
        HStack(spacing: 10) {
            ToolOptionsRow(model: model)
            Spacer(minLength: 4)
            if model.selection.count > 0 {
                SelectionActions(model: model, labels: labels && !compact)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

/// The active tool's options, generated from `model.toolOptions` (numbers, switches, short texts).
struct ToolOptionsRow: View {
    let model: DocumentModel

    private var keys: [String] {
        _ = model.toolOptionsTick
        return model.toolOptions.keys.sorted()
    }

    var body: some View {
        // `toolOptionsTick` is read so the row re-renders when the engine changes an option.
        let tick = model.toolOptionsTick
        HStack(spacing: 10) {
            Text(verbatim: toolName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .accessibilityIdentifier("contextBar.tool")
            ForEach(keys, id: \.self) { key in
                option(key: key, value: model.toolOptions[key])
            }
        }
        .id(tick)
    }

    private var toolName: String {
        for g in CommandCatalog.shared.toolGroups {
            if let t = g.tools.first(where: { $0.id == model.activeTool }) { return t.label }
        }
        return model.activeTool
    }

    @ViewBuilder
    private func option(key: String, value: Any?) -> some View {
        let title = Self.humanize(key)
        if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
            Toggle(title, isOn: Binding(get: { n.boolValue }, set: { model.setToolOption(key, $0) }))
                .toggleStyle(.button)
                .buttonStyle(.glass)
                .lineLimit(1)
                .accessibilityIdentifier("toolOption.\(key)")
        } else if let n = value as? NSNumber {
            let isInt = !"fd".contains(String(cString: n.objCType))
            NumberField(identifier: "toolOption.\(key)", label: title, value: n.doubleValue) { v in
                if isInt {
                    if let i = CommandForm.safeInt(v) { model.setToolOption(key, i) }
                } else {
                    model.setToolOption(key, v)
                }
            }
            .frame(width: 150)
        } else if let s = value as? String {
            HStack(spacing: 4) {
                Text(verbatim: title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(verbatim: s).font(.subheadline).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("toolOption.\(key)")
        }
    }

    static func humanize(_ key: String) -> String {
        var out = ""
        for (i, ch) in key.enumerated() {
            if ch == "_" { out.append(" "); continue }
            if ch.isUppercase && i > 0 { out.append(" ") }
            out.append(i == 0 ? (ch.uppercased().first ?? ch) : ch)
        }
        return out
    }
}

/// Selection quick actions: group, ungroup, arrange, align, Pathfinder, lock, delete.
struct SelectionActions: View {
    let model: DocumentModel
    var labels = true

    var body: some View {
        HStack(spacing: 6) {
            CommandIconButton(model: model, id: "object.group", title: "Group", symbol: "rectangle.3.group")
            CommandIconButton(model: model, id: "object.ungroup", title: "Ungroup", symbol: "rectangle.3.group.fill")
            arrangeMenu
            alignMenu
            pathfinderMenu
            CommandIconButton(model: model, id: "object.lock", title: "Lock", symbol: "lock")
            CommandIconButton(model: model, id: "edit.clear", title: "Delete", symbol: "trash")
        }
    }

    private func menuLabel(_ title: String, _ symbol: String) -> some View {
        Group {
            if labels {
                Label { Text(verbatim: title).lineLimit(1) } icon: { Image(systemName: symbol) }
            } else {
                Image(systemName: symbol).frame(minWidth: 28, minHeight: 24)
            }
        }
    }

    private var arrangeMenu: some View {
        Menu {
            CommandButton(model: model, id: "object.arrange.bringToFront", title: "Bring to Front", symbol: "square.3.layers.3d.top.filled")
            CommandButton(model: model, id: "object.arrange.bringForward", title: "Bring Forward", symbol: "square.2.layers.3d.top.filled")
            CommandButton(model: model, id: "object.arrange.sendBackward", title: "Send Backward", symbol: "square.2.layers.3d.bottom.filled")
            CommandButton(model: model, id: "object.arrange.sendToBack", title: "Send to Back", symbol: "square.3.layers.3d.bottom.filled")
        } label: { menuLabel("Arrange", "square.3.layers.3d") }
        .menuStyle(.button).buttonStyle(.glass)
        .accessibilityLabel("Arrange")
        .accessibilityIdentifier("contextBar.arrange")
    }

    private var alignMenu: some View {
        Menu {
            ForEach(AlignAction.all, id: \.title) { a in
                CommandButton(model: model, id: "object.align", title: a.title, symbol: a.symbol, params: a.params,
                              identifier: "contextBar.align.\(a.key)")
            }
        } label: { menuLabel("Align", "align.horizontal.center") }
        .menuStyle(.button).buttonStyle(.glass)
        .accessibilityLabel("Align")
        .accessibilityIdentifier("contextBar.align")
    }

    private var pathfinderMenu: some View {
        Menu {
            ForEach(PathfinderAction.all, id: \.id) { a in
                CommandButton(model: model, id: a.id, title: a.title, symbol: a.symbol)
            }
        } label: { menuLabel("Pathfinder", "square.on.square.dashed") }
        .menuStyle(.button).buttonStyle(.glass)
        .accessibilityLabel("Pathfinder")
        .accessibilityIdentifier("contextBar.pathfinder")
    }
}

struct AlignAction {
    let key: String
    let title: String
    let symbol: String
    let params: [String: String]

    static var all: [AlignAction] { [
        AlignAction(key: "left", title: "Align Left", symbol: "align.horizontal.left", params: ["horizontal": "left"]),
        AlignAction(key: "hcenter", title: "Align Horizontal Center", symbol: "align.horizontal.center", params: ["horizontal": "center"]),
        AlignAction(key: "right", title: "Align Right", symbol: "align.horizontal.right", params: ["horizontal": "right"]),
        AlignAction(key: "top", title: "Align Top", symbol: "align.vertical.top", params: ["vertical": "top"]),
        AlignAction(key: "vcenter", title: "Align Vertical Center", symbol: "align.vertical.center", params: ["vertical": "center"]),
        AlignAction(key: "bottom", title: "Align Bottom", symbol: "align.vertical.bottom", params: ["vertical": "bottom"]),
    ] }
}

struct PathfinderAction {
    let id: String
    let title: String
    let symbol: String

    static let all: [PathfinderAction] = [
        PathfinderAction(id: "object.pathfinder.unite", title: "Unite", symbol: "square.on.square"),
        PathfinderAction(id: "object.pathfinder.minusFront", title: "Minus Front", symbol: "square.dashed.inset.filled"),
        PathfinderAction(id: "object.pathfinder.intersect", title: "Intersect", symbol: "circle.circle"),
        PathfinderAction(id: "object.pathfinder.exclude", title: "Exclude", symbol: "circle.lefthalf.filled.righthalf.striped.horizontal"),
        PathfinderAction(id: "object.pathfinder.divide", title: "Divide", symbol: "square.split.2x2"),
        PathfinderAction(id: "object.pathfinder.trim", title: "Trim", symbol: "scissors"),
        PathfinderAction(id: "object.pathfinder.merge", title: "Merge", symbol: "arrow.triangle.merge"),
        PathfinderAction(id: "object.pathfinder.crop", title: "Crop", symbol: "crop"),
        PathfinderAction(id: "object.pathfinder.outline", title: "Outline", symbol: "square.dashed"),
        PathfinderAction(id: "object.pathfinder.minusBack", title: "Minus Back", symbol: "square.dashed.inset.filled"),
    ]
}
