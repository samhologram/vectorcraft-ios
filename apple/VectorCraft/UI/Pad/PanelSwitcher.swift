import SwiftUI
import VectorCraftKit

/// Panel switcher: one icon per hand-built panel (`panel.<id>`) and a menu with every other desktop panel.
/// Horizontal; scrolls only as a last resort.
struct PanelSwitcher: View {
    let model: DocumentModel

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(Panel.allCases) { panel in
                        let selected = model.activeGenericPanel == nil && model.activePanel == panel
                        Button {
                            model.activeGenericPanel = nil
                            model.activePanel = panel
                        } label: {
                            Image(systemName: CommandCatalog.shared.symbol(forPanel: panel.rawValue))
                                .frame(width: 30, height: 30)
                        }
                        .glassToggle(selected)
                        .help(title(panel))
                        .accessibilityLabel(title(panel))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("panel.\(panel.rawValue)")
                    }
                    morePanels
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func title(_ panel: Panel) -> String {
        CommandCatalog.shared.panels.first { $0.id == panel.rawValue }?.label ?? panel.rawValue.capitalized
    }

    @ViewBuilder
    private var morePanels: some View {
        let built = Set(Panel.allCases.map(\.rawValue))
        let rest = CommandCatalog.shared.panels.filter { !built.contains($0.id) }
        if !rest.isEmpty {
            Menu {
                ForEach(rest, id: \.id) { p in
                    Button {
                        model.activeGenericPanel = p.id
                    } label: {
                        Label(p.label, systemImage: CommandCatalog.shared.symbol(forPanel: p.id))
                    }
                    .accessibilityIdentifier("panel.\(p.id)")
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 30, height: 30)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .accessibilityLabel("More panels")
            .accessibilityIdentifier("panelSwitcher.more")
        }
    }
}
