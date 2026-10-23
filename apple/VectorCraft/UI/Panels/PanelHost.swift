import SwiftUI
import VectorCraftKit

/// The body of the active panel (no chrome). Any `panel_catalog` id without a hand-built page shows the generic
/// "commands of this panel" page, so every desktop panel is reachable.
struct ActivePanelView: View {
    let model: DocumentModel

    var body: some View {
        if let generic = model.activeGenericPanel {
            GenericPanelPage(model: model, panelID: generic)
        } else {
            switch model.activePanel {
            case .properties: PropertiesPanel(model: model)
            case .layers: LayersPanel(model: model)
            case .color: ColorPanel(model: model)
            case .swatches: SwatchesPanel(model: model)
            case .stroke: StrokePanel(model: model)
            case .gradient: GradientPanel(model: model)
            case .transparency: TransparencyPanel(model: model)
            case .appearance: AppearancePanel(model: model)
            case .align: AlignPanel(model: model)
            case .pathfinder: PathfinderPanel(model: model)
            case .transform: TransformPanel(model: model)
            case .artboards: ArtboardsPanel(model: model)
            case .character: CharacterPanel(model: model)
            case .paragraph: ParagraphPanel(model: model)
            case .history: HistoryPanel(model: model)
            case .symbols: SymbolsPanel(model: model)
            case .brushes: BrushesPanel(model: model)
            case .graphicStyles: GraphicStylesPanel(model: model)
            case .docInfo: DocInfoPanel(model: model)
            case .info: InfoPanel(model: model)
            case .navigator: NavigatorPanel(model: model)
            }
        }
    }
}

/// The active panel with a title bar, close button and (optionally) the panel switcher: the iPad inspector
/// column and the iPhone sheet.
struct PanelHost: View {
    let model: DocumentModel
    var showsSwitcher = false

    private var activeID: String { model.activeGenericPanel ?? model.activePanel.rawValue }
    private var title: String {
        CommandCatalog.shared.panels.first { $0.id == activeID }?.label ?? activeID.capitalized
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(title, systemImage: CommandCatalog.shared.symbol(forPanel: activeID))
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("panelTitle")
                Spacer()
                Button {
                    model.runUI("window.panel.close")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close panel")
                .accessibilityIdentifier("panel.close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            if showsSwitcher {
                PanelSwitcher(model: model)
            }
            ActivePanelView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector")
    }
}

/// Commands whose menu path relates to a panel without a hand-built page (e.g. Color Guide, Brushes libraries,
/// Variables): every one is a button, so the panel's features stay reachable.
struct GenericPanelPage: View {
    let model: DocumentModel
    let panelID: String

    private var panel: PanelInfo? { CommandCatalog.shared.panels.first { $0.id == panelID } }

    private var commands: [CatalogEntry] {
        guard let label = panel?.label.lowercased() else { return [] }
        let id = panelID.lowercased()
        return UICatalog.entries.filter { e in
            if e.isUI { return false }
            if e.menu.contains(where: { $0.lowercased() == label }) { return true }
            return e.id.lowercased().hasPrefix(id + ".")
        }
    }

    var body: some View {
        let list = commands
        if list.isEmpty {
            PanelEmpty(title: panel?.label ?? panelID, symbol: CommandCatalog.shared.symbol(forPanel: panelID),
                       message: "This panel has no commands on iPad and iPhone yet. Search the command palette for related features.")
                .accessibilityIdentifier("control.\(panelID).empty")
        } else {
            List {
                Section {
                    ForEach(list) { e in
                        Button {
                            model.present(e.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: e.label).foregroundStyle(.primary)
                                if e.isQuery { Text("Query").font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                        .disabled(UICatalog.unsupported(e.id) != nil || !model.isEnabled(e.id))
                        .accessibilityIdentifier("command.\(e.id)")
                    }
                } footer: {
                    Text("Commands of the \(panel?.label ?? panelID) panel.")
                }
            }
            .accessibilityIdentifier("control.\(panelID).commands")
        }
    }
}
