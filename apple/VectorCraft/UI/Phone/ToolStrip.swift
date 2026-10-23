import SwiftUI
import VectorCraftKit

/// iPhone: horizontally scrolling strip of tool groups (`toolStrip`), the fill / stroke wells first. A long press
/// on a group opens its other tools as a menu. Scrolling is the last resort, so nothing falls off a narrow screen.
struct ToolStrip: View {
    let model: DocumentModel

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    FillStrokeWells(model: model, compact: true)
                    Divider().frame(height: 32)
                    ForEach(Array(CommandCatalog.shared.toolGroups.enumerated()), id: \.offset) { _, group in
                        ToolGroupButton(model: model, group: group, edge: 38, usesPopover: false)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toolStrip")
    }
}
