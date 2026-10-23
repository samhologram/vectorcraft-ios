import SwiftUI
import VectorCraftKit

/// Fill / stroke switch shared by the colour pages.
struct PaintTargetPicker: View {
    @Environment(EditorUIState.self) private var ui
    let panelID: String

    var body: some View {
        @Bindable var ui = ui
        Picker("Edit", selection: $ui.paintTarget) {
            Text("Fill").tag(EditorUIState.PaintTarget.fill)
            Text("Stroke").tag(EditorUIState.PaintTarget.stroke)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("control.\(panelID).target")
    }
}

extension DocumentModel {
    func paint(for target: EditorUIState.PaintTarget) -> String? {
        target == .fill ? effectiveFill : effectiveStroke
    }
}

/// System colour picker, hex field and RGB sliders for the fill or stroke.
struct ColorPanel: View {
    let model: DocumentModel
    @Environment(EditorUIState.self) private var ui
    @State private var streamer = ColorStreamer()
    @State private var hexText = ""
    @FocusState private var hexFocused: Bool

    private var target: EditorUIState.PaintTarget { ui.paintTarget }
    private var paint: String? { model.paint(for: target) }
    private var color: Color { Color(vcHex: paint) ?? .black }
    private var setID: String { target == .fill ? "paint.setFill" : "paint.setStroke" }

    var body: some View {
        Form {
            Section {
                PaintTargetPicker(panelID: "color")
                HStack(spacing: 14) {
                    PaintChip(paint: paint, size: 44)
                    ColorPicker("Color", selection: Binding(
                        get: { color },
                        set: { streamer.send(model, target: target, hex: $0.vcHex) }
                    ), supportsOpacity: false)
                    .accessibilityIdentifier("control.color.picker")
                }
                HStack {
                    Text("Hex").foregroundStyle(.secondary)
                    TextField("#rrggbb", text: $hexText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($hexFocused)
                        .submitLabel(.done)
                        .onSubmit(applyHex)
                        .monospaced()
                        .accessibilityIdentifier("control.color.hex")
                }
                Button {
                    model.run(setID, ["none": true])
                } label: {
                    Label("None", systemImage: "nosign")
                }
                .accessibilityIdentifier("control.color.none")
            }
            if let rgb = rgb {
                Section("RGB") {
                    channel("Red", index: 0, value: rgb.0, id: "red")
                    channel("Green", index: 1, value: rgb.1, id: "green")
                    channel("Blue", index: 2, value: rgb.2, id: "blue")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { hexText = paint ?? "" }
        .onChange(of: paint) { _, new in if !hexFocused { hexText = new ?? "" } }
        .accessibilityIdentifier("control.color")
    }

    private var rgb: (Double, Double, Double)? {
        guard let p = paint, Color(vcHex: p) != nil else { return nil }
        var s = p
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }

    private func channel(_ title: String, index: Int, value: Double, id: String) -> some View {
        DragSlider(
            identifier: "control.color.\(id)",
            label: title,
            range: 0...255,
            value: value,
            step: 1,
            onBegin: { model.beginDrag("Set Color") },
            onChange: { v in
                guard var c = rgb.map({ [$0.0, $0.1, $0.2] }) else { return }
                c[index] = v
                let hex = String(format: "#%02x%02x%02x", Int(c[0]), Int(c[1]), Int(c[2]))
                model.preview(setID, ["color": hex])
            },
            onEnd: { model.endDrag() }
        )
    }

    private func applyHex() {
        let t = hexText.trimmingCharacters(in: .whitespaces)
        let hex = t.hasPrefix("#") ? t : "#" + t
        guard Color(vcHex: hex) != nil else { hexText = paint ?? ""; return }
        model.run(setID, ["color": hex])
    }
}

/// The document's swatches as a grid; tap applies to the fill or stroke.
struct SwatchesPanel: View {
    let model: DocumentModel
    @Environment(EditorUIState.self) private var ui
    @State private var swatches: [Swatch] = []

    struct Swatch: Identifiable {
        let index: Int
        let name: String
        let kind: String
        let hex: String?
        let global: Bool
        let spot: Bool
        var id: Int { index }
    }

    var body: some View {
        Form {
            Section {
                PaintTargetPicker(panelID: "swatches")
            }
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                    ForEach(swatches) { s in
                        Button {
                            apply(s)
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                PaintChip(paint: chipPaint(s), size: 40)
                                if s.spot || s.global {
                                    Image(systemName: s.spot ? "circle.fill" : "triangle.fill")
                                        .font(.system(size: 7))
                                        .foregroundStyle(.white)
                                        .padding(2)
                                        .shadow(radius: 1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(s.name)
                        .accessibilityIdentifier("control.swatches.item.\(s.index)")
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Button {
                    model.pendingParams = [:]
                    model.pendingCommand = "swatch.new"
                } label: { Label("New Swatch…", systemImage: "plus") }
                .accessibilityIdentifier("command.swatch.new")
                Button {
                    model.present("swatch.addUsedColors")
                } label: { Label("Add Used Colors", systemImage: "paintpalette") }
                .accessibilityIdentifier("command.swatch.addUsedColors")
            }
        }
        .task(id: model.state.historyId) { load() }
        .accessibilityIdentifier("control.swatches")
    }

    private func chipPaint(_ s: Swatch) -> String? {
        switch s.kind {
        case "color": return s.hex
        case "gradient": return "gradient"
        case "pattern": return "pattern"
        default: return nil
        }
    }

    private func load() {
        guard let out = model.quietQuery("swatch.list") as? [String: Any],
              let list = out["swatches"] as? [[String: Any]] else { swatches = []; return }
        swatches = list.enumerated().map { i, d in
            Swatch(index: i, name: jsonString(d["name"]) ?? "", kind: jsonString(d["kind"]) ?? "color",
                   hex: jsonString(d["hex"]), global: jsonBool(d["global"]) ?? false, spot: jsonBool(d["spot"]) ?? false)
        }
    }

    private func apply(_ s: Swatch) {
        let id = ui.paintTarget == .fill ? "paint.setFill" : "paint.setStroke"
        if s.kind == "none" {
            model.run(id, ["none": true])
        } else {
            model.run(id, ["swatch": s.name])
        }
    }
}
