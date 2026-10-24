import SwiftUI
import VectorCraftKit

/// iPhone layout (also iPad windows narrower than 700 pt): compact context bar, the canvas, a scrolling tool strip
/// at the bottom. Panels open in a bottom sheet with detents that keep the canvas visible and interactive.
struct PhoneEditorView: View {
    @Bindable var model: DocumentModel

    @State private var detent: PresentationDetent = .fraction(Self.smallDetent)

    private static let smallDetent: CGFloat = 0.35

    var body: some View {
        VStack(spacing: 0) {
            ContextBar(model: model, compact: true)
            CanvasView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ToolStrip(model: model)
        }
        .sheet(isPresented: $model.phoneSheetPresented) {
            PanelHost(model: model, showsSwitcher: true)
                .presentationDetents([.fraction(Self.smallDetent), .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
    }
}
