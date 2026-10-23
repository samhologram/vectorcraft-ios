import SwiftUI
import VectorCraftKit

/// Stroke options: weight, cap, join, alignment, dashes, width profile. Reads the first selected object's
/// `strokeOptions` (`document.node`); with nothing selected the changes set up the next object drawn.
struct StrokePanel: View {
    let model: DocumentModel

    @State private var options: [String: Any] = [:]
    @State private var dashOn = false
    @State private var dash = 12.0
    @State private var gap = 6.0

    private static let profiles = ["uniform", "lens", "taperStart", "taperEnd", "pinch", "teardrop", "wave"]

    var body: some View {
        Form {
            Section {
                StrokeWeightControl(model: model, panelID: "stroke")
                NumberField(identifier: "control.stroke.weightField", label: "Weight", value: model.selection.strokeWidth ?? 1, unit: "pt") {
                    model.run("stroke.set", ["weight": max(0, $0)])
                }
            }
            Section("Corners and Caps") {
                picker("Cap", key: "cap", values: ["butt", "round", "square"], titles: ["Butt", "Round", "Projecting"])
                picker("Corner", key: "join", values: ["miter", "round", "bevel"], titles: ["Miter", "Round", "Bevel"])
                if (options["join"] as? String ?? "miter") == "miter" {
                    NumberField(identifier: "control.stroke.miterLimit", label: "Miter Limit", value: jsonNumber(options["miterLimit"]) ?? 10) {
                        model.run("stroke.set", ["miterLimit": max(1, $0)])
                    }
                }
                picker("Align", key: "align", values: ["center", "inside", "outside"], titles: ["Center", "Inside", "Outside"])
            }
            Section("Dashed Line") {
                Toggle("Dashed", isOn: Binding(get: { dashOn }, set: { dashOn = $0; applyDash() }))
                    .accessibilityIdentifier("control.stroke.dashed")
                if dashOn {
                    NumberField(identifier: "control.stroke.dash", label: "Dash", value: dash, unit: "pt") { dash = max(0, $0); applyDash() }
                    NumberField(identifier: "control.stroke.gap", label: "Gap", value: gap, unit: "pt") { gap = max(0, $0); applyDash() }
                }
            }
            Section("Profile") {
                Picker("Width Profile", selection: Binding(
                    get: { options["profile"] as? String ?? "uniform" },
                    set: { model.run("stroke.set", ["profile": $0]) }
                )) {
                    ForEach(Self.profiles, id: \.self) { Text(verbatim: ToolOptionsRow.humanize($0)).tag($0) }
                }
                .accessibilityIdentifier("control.stroke.profile")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: model.selectionKey) { load() }
        .accessibilityIdentifier("control.stroke")
    }

    private func picker(_ title: String, key: String, values: [String], titles: [String]) -> some View {
        Picker(title, selection: Binding(
            get: { options[key] as? String ?? values[0] },
            set: { model.run("stroke.set", [key: $0]) }
        )) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in Text(verbatim: titles[i]).tag(v) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("control.stroke.\(key)")
    }

    private func load() {
        let node = model.firstSelectedNode()
        options = node?["strokeOptions"] as? [String: Any] ?? [:]
        if let d = options["dash"] as? [Any], !d.isEmpty {
            dashOn = true
            dash = jsonNumber(d[0]) ?? 12
            gap = jsonNumber(d.count > 1 ? d[1] : d[0]) ?? 6
        } else {
            dashOn = false
        }
    }

    private func applyDash() {
        if dashOn {
            model.run("stroke.set", ["dash": [dash, gap]])
        } else {
            model.run("stroke.set", ["dash": NSNull()])
        }
    }
}
