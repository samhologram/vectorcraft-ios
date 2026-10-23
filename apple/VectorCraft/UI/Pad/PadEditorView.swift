import SwiftUI
import VectorCraftKit

/// iPad layout: tool palette on the leading edge, context bar over the canvas, inspector on the trailing edge.
/// (`EditorRootView` falls back to the iPhone layout when the window is narrower than 700 pt.)
struct PadEditorView: View {
    @Bindable var model: DocumentModel

    var body: some View {
        HStack(spacing: 0) {
            ToolPalette(model: model)
            VStack(spacing: 0) {
                ContextBar(model: model)
                CanvasView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .inspector(isPresented: $model.inspectorVisible) {
            PanelHost(model: model, showsSwitcher: true)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
    }
}
