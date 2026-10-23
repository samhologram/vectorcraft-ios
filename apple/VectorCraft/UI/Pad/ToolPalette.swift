import SwiftUI
import VectorCraftKit

/// iPad: vertical tool palette on the leading edge, one button per tool group, then the fill / stroke wells.
/// It gets denser when the window is short and scrolls only as a last resort, so no button is out of reach.
struct ToolPalette: View {
    let model: DocumentModel

    /// Button edge and gap, densest last; the first that fits the window height wins.
    private static let densities: [(edge: CGFloat, gap: CGFloat)] = [(44, 8), (38, 6), (32, 4)]

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(Array(Self.densities.enumerated()), id: \.offset) { _, d in
                column(edge: d.edge, gap: d.gap, compact: d.edge < 40)
            }
            ScrollView(.vertical) {
                column(edge: 32, gap: 4, compact: true)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 66)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toolPalette")
    }

    private func column(edge: CGFloat, gap: CGFloat, compact: Bool) -> some View {
        GlassEffectContainer(spacing: gap) {
            VStack(spacing: gap) {
                ForEach(Array(CommandCatalog.shared.toolGroups.enumerated()), id: \.offset) { _, group in
                    ToolGroupButton(model: model, group: group, edge: edge)
                }
                Divider().frame(width: 32)
                FillStrokeWells(model: model, compact: compact)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }
}
