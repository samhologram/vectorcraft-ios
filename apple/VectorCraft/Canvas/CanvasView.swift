import SwiftUI

/// The document canvas: the engine's rendering of the current view, tool overlays, touch / Pencil / pointer /
/// keyboard input, and the pinch / pan gestures (CONTRACT §4). All state lives in `DocumentModel`.
struct CanvasView: View {
    let model: DocumentModel

    var body: some View {
        CanvasRepresentable(model: model)
            // The on-screen keyboard (Type tool) must not resize the canvas under the artwork.
            .ignoresSafeArea(.keyboard)
            .accessibilityIdentifier("canvas")
    }
}

private struct CanvasRepresentable: UIViewRepresentable {
    let model: DocumentModel

    func makeUIView(context: Context) -> CanvasUIView {
        CanvasUIView(model: model)
    }

    func updateUIView(_ uiView: CanvasUIView, context: Context) {
        uiView.model = model
        uiView.apply()
    }
}
