import SwiftUI
import VectorCraftKit

/// Align and distribute, to the selection, the artboard or the key object.
struct AlignPanel: View {
    let model: DocumentModel

    @State private var to = "selection"
    @State private var spacing = 10.0

    var body: some View {
        Form {
            Section {
                NeedsSelectionNote(model: model)
                Picker("Align To", selection: $to) {
                    Text("Selection").tag("selection")
                    Text("Artboard").tag("artboard")
                    Text("Key Object").tag("key")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("control.align.to")
            }
            Section("Align Objects") {
                AlignGrid(model: model, to: to)
            }
            Section("Distribute Objects") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                    ForEach(Self.distribute, id: \.key) { d in
                        CommandIconButton(model: model, id: "object.distribute", title: d.title, symbol: d.symbol,
                                          params: d.params.merging(["to": to]) { a, _ in a },
                                          identifier: "contextBar.distribute.\(d.key)")
                    }
                }
            }
            Section("Distribute Spacing") {
                NumberField(identifier: "control.align.spacing", label: "Spacing", value: spacing, unit: "pt") { spacing = $0 }
                HStack(spacing: 8) {
                    CommandIconButton(model: model, id: "object.distributeSpacing", title: "Horizontal Spacing", symbol: "distribute.horizontal.center",
                                      params: ["axis": "horizontal", "spacing": spacing], identifier: "contextBar.distributeSpacing.horizontal")
                    CommandIconButton(model: model, id: "object.distributeSpacing", title: "Vertical Spacing", symbol: "distribute.vertical.center",
                                      params: ["axis": "vertical", "spacing": spacing], identifier: "contextBar.distributeSpacing.vertical")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("control.align")
    }

    private struct Dist {
        let key: String
        let title: String
        let symbol: String
        let params: [String: String]
    }

    private static var distribute: [Dist] { [
        Dist(key: "left", title: "Distribute Left Edges", symbol: "align.horizontal.left", params: ["horizontal": "left"]),
        Dist(key: "hcenter", title: "Distribute Horizontal Centers", symbol: "distribute.horizontal.center", params: ["horizontal": "center"]),
        Dist(key: "right", title: "Distribute Right Edges", symbol: "align.horizontal.right", params: ["horizontal": "right"]),
        Dist(key: "top", title: "Distribute Top Edges", symbol: "align.vertical.top", params: ["vertical": "top"]),
        Dist(key: "vcenter", title: "Distribute Vertical Centers", symbol: "distribute.vertical.center", params: ["vertical": "center"]),
        Dist(key: "bottom", title: "Distribute Bottom Edges", symbol: "align.vertical.bottom", params: ["vertical": "bottom"]),
    ] }
}

/// Shape modes and Pathfinder operations, compound paths, clipping masks.
struct PathfinderPanel: View {
    let model: DocumentModel

    var body: some View {
        Form {
            Section {
                NeedsSelectionNote(model: model)
            }
            Section("Shape Modes") {
                PathfinderGrid(model: model, items: Array(PathfinderAction.all.prefix(4)))
            }
            Section("Pathfinders") {
                PathfinderGrid(model: model, items: Array(PathfinderAction.all.dropFirst(4)))
            }
            Section("Compound and Mask") {
                CommandButton(model: model, id: "object.compoundPath.make", title: "Make Compound Path")
                CommandButton(model: model, id: "object.compoundPath.release", title: "Release Compound Path")
                CommandButton(model: model, id: "object.clippingMask.make", title: "Make Clipping Mask")
                CommandButton(model: model, id: "object.clippingMask.release", title: "Release Clipping Mask")
            }
        }
        .accessibilityIdentifier("control.pathfinder")
    }
}

/// Position and size, rotate, scale, shear, flip.
struct TransformPanel: View {
    let model: DocumentModel

    @State private var angle = 15.0
    @State private var scaleX = 100.0
    @State private var scaleY = 100.0
    @State private var uniform = true
    @State private var shear = 15.0

    var body: some View {
        Form {
            Section {
                NeedsSelectionNote(model: model)
                TransformFields(model: model, panelID: "transform")
            }
            Section("Rotate") {
                NumberField(identifier: "control.transform.angle", label: "Angle", value: angle, unit: "°", enabled: model.selection.count > 0) { angle = $0 }
                HStack {
                    Button {
                        model.run("object.rotate", ["angle": angle])
                    } label: { Label("Rotate", systemImage: "arrow.counterclockwise") }
                    .accessibilityIdentifier("control.transform.rotate")
                    Spacer()
                    Button {
                        model.run("object.rotate", ["angle": 90])
                    } label: { Image(systemName: "rotate.left") }
                    .accessibilityLabel("Rotate 90° left")
                    .accessibilityIdentifier("control.transform.rotateLeft")
                    Button {
                        model.run("object.rotate", ["angle": -90])
                    } label: { Image(systemName: "rotate.right") }
                    .accessibilityLabel("Rotate 90° right")
                    .accessibilityIdentifier("control.transform.rotateRight")
                }
                .buttonStyle(.glass)
                .disabled(model.selection.count == 0)
            }
            Section("Scale") {
                NumberField(identifier: "control.transform.scaleX", label: "Width", value: scaleX, unit: "%", enabled: model.selection.count > 0) {
                    scaleX = $0
                    if uniform { scaleY = $0 }
                }
                NumberField(identifier: "control.transform.scaleY", label: "Height", value: scaleY, unit: "%", enabled: model.selection.count > 0 && !uniform) { scaleY = $0 }
                Toggle("Uniform", isOn: $uniform)
                    .accessibilityIdentifier("control.transform.uniform")
                Button {
                    model.run("object.scale", ["sx": scaleX, "sy": uniform ? scaleX : scaleY])
                } label: { Label("Scale", systemImage: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(.glass)
                .disabled(model.selection.count == 0)
                .accessibilityIdentifier("control.transform.scale")
            }
            Section("Shear and Flip") {
                NumberField(identifier: "control.transform.shear", label: "Shear", value: shear, unit: "°", enabled: model.selection.count > 0) { shear = $0 }
                HStack(spacing: 8) {
                    Button {
                        model.run("object.shear", ["angle": shear])
                    } label: { Text("Shear") }
                    .accessibilityIdentifier("control.transform.shearApply")
                    Button {
                        model.run("object.reflect", ["axis": "vertical"])
                    } label: { Label("Flip Horizontal", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    .accessibilityIdentifier("control.transform.flipH")
                    Button {
                        model.run("object.reflect", ["axis": "horizontal"])
                    } label: { Label("Flip Vertical", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") }
                    .accessibilityIdentifier("control.transform.flipV")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .disabled(model.selection.count == 0)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("control.transform")
    }
}
