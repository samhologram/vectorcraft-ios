import SwiftUI
import VectorCraftKit

/// Identity of "what is selected, at which history step": panels reload engine data when it changes.
struct SelectionKey: Hashable {
    let history: UInt64
    let ids: [UInt64]
}

extension DocumentModel {
    var selectionKey: SelectionKey { SelectionKey(history: state.historyId, ids: selection.ids) }
}

/// Opacity slider (one undo step per drag) for the selection, or the next object drawn when nothing is selected.
struct OpacityControl: View {
    let model: DocumentModel
    let panelID: String

    var body: some View {
        DragSlider(
            identifier: "control.\(panelID).opacity",
            label: "Opacity",
            range: 0...100,
            value: (model.selection.opacity ?? 1) * 100,
            step: 1,
            unit: " %",
            onBegin: { model.beginDrag("Opacity") },
            onChange: { model.preview("transparency.set", ["opacity": $0]) },
            onEnd: { model.endDrag() }
        )
        .disabled(model.selection.count == 0)
    }
}

/// Stroke weight: slider + field.
struct StrokeWeightControl: View {
    let model: DocumentModel
    let panelID: String

    var body: some View {
        let weight = model.selection.strokeWidth ?? 1
        VStack(spacing: 6) {
            DragSlider(
                identifier: panelID == "stroke" ? "control.stroke.width" : "control.\(panelID).strokeWidth",
                label: "Stroke Weight",
                range: 0...50,
                value: weight,
                step: 0.25,
                decimals: 2,
                unit: " pt",
                onBegin: { model.beginDrag("Stroke Weight") },
                onChange: { model.preview("stroke.set", ["weight": $0]) },
                onEnd: { model.endDrag() }
            )
        }
    }
}

/// X / Y / W / H fields (Transform panel and Properties): the selection's bounds through `object.setBounds`.
struct TransformFields: View {
    let model: DocumentModel
    let panelID: String
    @State private var proportional = false

    var body: some View {
        let b = model.selection.bounds
        let enabled = b != nil
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                NumberField(identifier: "control.\(panelID).x", label: "X", value: b?.x ?? 0, unit: "pt", enabled: enabled) { send(["x": $0]) }
                NumberField(identifier: "control.\(panelID).y", label: "Y", value: b?.y ?? 0, unit: "pt", enabled: enabled) { send(["y": $0]) }
            }
            HStack(spacing: 10) {
                NumberField(identifier: "control.\(panelID).width", label: "W", value: b?.width ?? 0, unit: "pt", enabled: enabled) { send(["width": $0]) }
                NumberField(identifier: "control.\(panelID).height", label: "H", value: b?.height ?? 0, unit: "pt", enabled: enabled) { send(["height": $0]) }
            }
            Toggle("Keep Proportions", isOn: $proportional)
                .font(.subheadline)
                .disabled(!enabled)
                .accessibilityIdentifier("control.\(panelID).proportional")
        }
    }

    private func send(_ values: [String: Any]) {
        var p = values
        p["reference"] = 0
        if proportional { p["proportional"] = true }
        model.run("object.setBounds", p)
    }
}

/// Six align buttons.
struct AlignGrid: View {
    let model: DocumentModel
    var to: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
            ForEach(AlignAction.all, id: \.key) { a in
                CommandIconButton(model: model, id: "object.align", title: a.title, symbol: a.symbol, params: merged(a.params),
                                  identifier: "command.object.align.\(a.key)")
            }
        }
    }
}

extension AlignGrid {
    fileprivate func merged(_ base: [String: Any]) -> [String: Any] {
        var p = base
        if let to { p["to"] = to }
        return p
    }
}

/// Pathfinder buttons with labels.
struct PathfinderGrid: View {
    let model: DocumentModel
    let items: [PathfinderAction]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.id) { a in
                Button {
                    model.present(a.id)
                } label: {
                    Label { Text(verbatim: a.title).lineLimit(1) } icon: { Image(systemName: a.symbol) }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(!model.isEnabled(a.id))
                .accessibilityIdentifier("command.\(a.id)")
            }
        }
    }
}

/// Arrange buttons.
struct ArrangeRow: View {
    let model: DocumentModel

    var body: some View {
        HStack(spacing: 8) {
            CommandIconButton(model: model, id: "object.arrange.bringToFront", title: "Bring to Front", symbol: "square.3.layers.3d.top.filled")
            CommandIconButton(model: model, id: "object.arrange.bringForward", title: "Bring Forward", symbol: "square.2.layers.3d.top.filled")
            CommandIconButton(model: model, id: "object.arrange.sendBackward", title: "Send Backward", symbol: "square.2.layers.3d.bottom.filled")
            CommandIconButton(model: model, id: "object.arrange.sendToBack", title: "Send to Back", symbol: "square.3.layers.3d.bottom.filled")
        }
    }
}

/// "Select something" placeholder shown at the top of selection-dependent pages.
struct NeedsSelectionNote: View {
    let model: DocumentModel
    var body: some View {
        if model.selection.count == 0 {
            Label("Select an object to edit it.", systemImage: "cursorarrow.click")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("control.needsSelection")
        }
    }
}
