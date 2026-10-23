import SwiftUI
import VectorCraftKit

/// Gradient editor: kind, angle, colour stops; Apply sets it on the fill or stroke.
struct GradientPanel: View {
    let model: DocumentModel
    @Environment(EditorUIState.self) private var ui

    struct Stop: Identifiable {
        var id = UUID()
        var offset: Double
        var color: Color
    }

    @State private var kind = "linear"
    @State private var angle = 0.0
    // Default stops are document colour values (white to black), not UI chrome.
    @State private var stops: [Stop] = [Stop(offset: 0, color: .white), Stop(offset: 1, color: .black)]

    var body: some View {
        Form {
            Section {
                PaintTargetPicker(panelID: "gradient")
                preview
                Picker("Type", selection: $kind) {
                    Text("Linear").tag("linear")
                    Text("Radial").tag("radial")
                    Text("Freeform").tag("freeform")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("control.gradient.kind")
                if kind == "linear" {
                    DragSlider(identifier: "control.gradient.angle", label: "Angle", range: -180...180, value: angle, step: 1, unit: "°",
                               onChange: { angle = $0 })
                }
            }
            Section("Stops") {
                ForEach($stops) { $stop in
                    HStack {
                        let n = stops.firstIndex { $0.id == stop.id } ?? 0
                        ColorPicker("Stop color", selection: $stop.color, supportsOpacity: false).labelsHidden()
                            .accessibilityIdentifier("control.gradient.stop.\(n).color")
                        Slider(value: $stop.offset, in: 0...1)
                            .accessibilityLabel("Stop position")
                            .accessibilityIdentifier("control.gradient.stop.\(n).offset")
                        Text(verbatim: "\(Int(stop.offset * 100))%").font(.caption.monospacedDigit()).frame(width: 40, alignment: .trailing)
                    }
                }
                .onDelete { if stops.count - $0.count >= 2 { stops.remove(atOffsets: $0) } }
                Button {
                    stops.append(Stop(offset: 0.5, color: .gray))
                } label: { Label("Add Stop", systemImage: "plus") }
                .accessibilityIdentifier("control.gradient.addStop")
                Button {
                    stops = stops.map { Stop(id: $0.id, offset: 1 - $0.offset, color: $0.color) }.sorted { $0.offset < $1.offset }
                } label: { Label("Reverse", systemImage: "arrow.left.arrow.right") }
                .accessibilityIdentifier("control.gradient.reverse")
            }
            Section {
                Button {
                    apply()
                } label: { Label("Apply Gradient", systemImage: "checkmark") }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("control.gradient.apply")
            }
        }
        .accessibilityIdentifier("control.gradient")
    }

    private var preview: some View {
        let colors = stops.sorted { $0.offset < $1.offset }.map { Gradient.Stop(color: $0.color, location: $0.offset) }
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(kind == "radial"
                  ? AnyShapeStyle(RadialGradient(stops: colors, center: .center, startRadius: 0, endRadius: 80))
                  : AnyShapeStyle(LinearGradient(stops: colors, startPoint: .leading, endPoint: .trailing)))
            .frame(height: 36)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.primary.opacity(0.3)))
            .accessibilityHidden(true)
    }

    private func apply() {
        let sorted = stops.sorted { $0.offset < $1.offset }
        var gradient: [String: Any] = [
            "kind": kind,
            "stops": sorted.map { ["offset": $0.offset, "color": $0.color.vcHex] as [String: Any] },
        ]
        if kind == "linear" { gradient["angle"] = angle }
        model.run(ui.paintTarget == .fill ? "paint.setFill" : "paint.setStroke", ["gradient": gradient])
    }
}
