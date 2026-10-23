import SwiftUI
import VectorCraftKit

/// Opacity and blend mode of the selection, plus isolate / knockout group switches.
struct TransparencyPanel: View {
    let model: DocumentModel

    @State private var blend = "Normal"
    @State private var isolate = false
    @State private var knockout = false

    private static let modes = [
        "Normal", "Darken", "Multiply", "Color Burn", "Lighten", "Screen", "Color Dodge", "Overlay",
        "Soft Light", "Hard Light", "Difference", "Exclusion", "Hue", "Saturation", "Color", "Luminosity",
    ]

    var body: some View {
        Form {
            Section {
                NeedsSelectionNote(model: model)
                OpacityControl(model: model, panelID: "transparency")
                Picker("Blend Mode", selection: Binding(
                    get: { blend },
                    set: { blend = $0; model.run("transparency.set", ["blend": $0]) }
                )) {
                    ForEach(Self.modes, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .disabled(model.selection.count == 0)
                .accessibilityIdentifier("control.transparency.blend")
            }
            Section("Groups") {
                Toggle("Isolate Blending", isOn: Binding(get: { isolate }, set: { isolate = $0; model.run("transparency.set", ["isolate": $0]) }))
                    .accessibilityIdentifier("control.transparency.isolate")
                Toggle("Knockout Group", isOn: Binding(get: { knockout }, set: { knockout = $0; model.run("transparency.set", ["knockout": $0]) }))
                    .accessibilityIdentifier("control.transparency.knockout")
            }
            .disabled(model.selection.count == 0)
            Section("Opacity Mask") {
                CommandButton(model: model, id: "transparency.makeOpacityMask", title: "Make Mask")
                CommandButton(model: model, id: "transparency.releaseOpacityMask", title: "Release Mask")
            }
        }
        .task(id: model.selectionKey) { load() }
        .accessibilityIdentifier("control.transparency")
    }

    private func load() {
        let node = model.firstSelectedNode()
        blend = node?["blend"] as? String ?? "Normal"
        if let info = model.quietQuery("transparency.info") as? [String: Any] {
            isolate = jsonBool(info["isolate"]) ?? false
            if let k = info["knockout"] as? String { knockout = k == "on" } else { knockout = jsonBool(info["knockout"]) ?? false }
        }
    }
}
