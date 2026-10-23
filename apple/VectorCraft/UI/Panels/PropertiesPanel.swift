import SwiftUI
import VectorCraftKit

/// Contextual page: shows what applies to the selection (paint, stroke, opacity, transform, align, arrange,
/// Pathfinder), or the defaults for the next object when nothing is selected.
struct PropertiesPanel: View {
    let model: DocumentModel

    var body: some View {
        Form {
            Section {
                HStack {
                    FillStrokeWells(model: model)
                    Spacer()
                    if model.selection.count > 0 {
                        Text(verbatim: summary).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("control.properties.summary")
                    }
                }
                StrokeWeightControl(model: model, panelID: "properties")
                OpacityControl(model: model, panelID: "properties")
            } header: {
                Text(model.selection.count > 0 ? "Appearance" : "Next Object")
            } footer: {
                if model.selection.count == 0 {
                    Text("Nothing is selected: these set up the next object you draw.")
                }
            }
            if model.selection.count > 0 {
                Section("Transform") {
                    TransformFields(model: model, panelID: "properties")
                }
                Section("Align") {
                    AlignGrid(model: model, to: model.selection.count == 1 ? "artboard" : nil)
                }
                Section("Arrange") {
                    ArrangeRow(model: model)
                }
                Section("Pathfinder") {
                    PathfinderGrid(model: model, items: Array(PathfinderAction.all.prefix(6)))
                }
                Section("Object") {
                    HStack(spacing: 8) {
                        CommandIconButton(model: model, id: "object.group", title: "Group", symbol: "rectangle.3.group")
                        CommandIconButton(model: model, id: "object.ungroup", title: "Ungroup", symbol: "rectangle.3.group.fill")
                        CommandIconButton(model: model, id: "object.lock", title: "Lock", symbol: "lock")
                        CommandIconButton(model: model, id: "object.hide", title: "Hide", symbol: "eye.slash")
                        CommandIconButton(model: model, id: "edit.clear", title: "Delete", symbol: "trash")
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("control.properties")
    }

    private var summary: String {
        let n = model.selection.count
        let kinds = model.selection.kinds.joined(separator: ", ")
        return "\(n) selected" + (kinds.isEmpty ? "" : "\n\(kinds)")
    }
}
