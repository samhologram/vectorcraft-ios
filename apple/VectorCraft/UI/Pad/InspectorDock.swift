import SwiftUI
import VectorCraftKit

/// Persistent iPad panel dock. Selection is always visible in both the vertical stack and its tab strip.
struct InspectorDock: View {
    let model: DocumentModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Panels").font(.headline)
                Spacer()
                Menu {
                    ForEach(CommandCatalog.shared.panels, id: \.id) { panel in
                        Button { model.showDockPanel(panel.id) } label: {
                            Label(panel.label, systemImage: CommandCatalog.shared.symbol(forPanel: panel.id))
                        }
                        .accessibilityIdentifier("panel.\(panel.id)")
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Add panel")
                .accessibilityIdentifier("control.panelMenu")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            if model.panelGroups.isEmpty {
                ContentUnavailableView("No Panels", systemImage: "rectangle.stack",
                                       description: Text("Add a panel with the plus button."))
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(model.panelGroups.enumerated()), id: \.element.id) { index, group in
                                DockPanelGroup(model: model, group: group, index: index)
                                    .id(group.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: model.panelRevealRevision, initial: true) { _, _ in
                        guard let shown = model.lastShownPanel,
                              let group = model.panelGroups.first(where: { $0.tabs.contains(shown) }) else { return }
                        withAnimation(.smooth) { reader.scrollTo(group.id, anchor: .top) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector")
    }
}

private struct DockPanelGroup: View {
    let model: DocumentModel
    let group: PanelGroup
    let index: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ScrollViewReader { reader in
                    ScrollView(.horizontal) {
                        HStack(spacing: 3) {
                            ForEach(group.tabs, id: \.self) { id in
                                Button {
                                    model.showDockPanel(id)
                                } label: {
                                    Text(panelTitle(id)).lineLimit(1)
                                        .padding(.horizontal, 8).frame(height: 38)
                                }
                                .buttonStyle(.plain)
                                .background(group.selected == id ? Color.accentColor.opacity(0.18) : Color.clear,
                                            in: .rect(cornerRadius: 8))
                                .accessibilityAddTraits(group.selected == id ? .isSelected : [])
                                .accessibilityIdentifier("panel.\(id)")
                                .id(id)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: model.panelRevealRevision, initial: true) { _, _ in
                        withAnimation(.smooth) { reader.scrollTo(group.selected, anchor: .center) }
                    }
                }
                Button { model.toggleDockGroup(group.id) } label: {
                    Image(systemName: group.collapsed ? "chevron.right" : "chevron.down")
                        .frame(width: 30, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(group.collapsed ? "Expand panel group" : "Collapse panel group")
                .accessibilityIdentifier("panelHeader.\(group.selected)")
                Menu {
                    panelActions
                    if !actions(for: group.selected).isEmpty { Divider() }
                    Button("Move Up", systemImage: "arrow.up") { model.moveDockGroup(group.id, by: -1) }
                        .disabled(index == 0)
                    Button("Move Down", systemImage: "arrow.down") { model.moveDockGroup(group.id, by: 1) }
                        .disabled(index == model.panelGroups.count - 1)
                    ForEach(model.panelGroups.filter { $0.id != group.id }) { destination in
                        Button("Move Tab to \(panelTitle(destination.selected))") {
                            model.moveDockTab(group.selected, toGroup: destination.id)
                        }
                    }
                    Divider()
                    Button("Close \(panelTitle(group.selected))", systemImage: "xmark") {
                        model.hideDockPanel(group.selected)
                    }
                    .accessibilityIdentifier("panelClose.\(group.selected)")
                } label: {
                    Image(systemName: "ellipsis").frame(width: 30, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Panel actions")
                .accessibilityIdentifier("panelActions.\(group.selected)")
            }
            .padding(.horizontal, 4)
            .background(.bar)
            if !group.collapsed {
                Divider()
                ActivePanelView(model: model, panelID: group.selected)
                    .frame(minHeight: 220, idealHeight: group.selected == "layers" ? 380 : 270)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("panelBody.\(group.selected)")
            }
        }
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func panelTitle(_ id: String) -> String {
        CommandCatalog.shared.panels.first(where: { $0.id == id })?.label ?? id.capitalized
    }

    private func actions(for id: String) -> [(String, String)] {
        switch id {
        case "layers": return [("layer.new", "New Layer"), ("layer.newSublayer", "New Sublayer"),
                               ("layer.delete", "Delete Selection")]
        case "swatches": return [("swatch.new", "New Swatch")]
        case "artboards": return [("artboard.new", "New Artboard"), ("artboard.delete", "Delete Artboard")]
        case "symbols": return [("symbol.new", "New Symbol")]
        case "brushes": return [("brush.new", "New Brush")]
        case "graphicStyles": return [("graphicStyle.new", "New Graphic Style")]
        case "appearance": return [("appearance.addFill", "Add Fill"),
                                   ("appearance.addStroke", "Add Stroke"),
                                   ("appearance.addEffect", "Add Effect")]
        default: return []
        }
    }

    @ViewBuilder private var panelActions: some View {
        ForEach(actions(for: group.selected), id: \.0) { action in
            Button(action.1) { model.present(action.0) }
                .disabled(!model.isEnabled(action.0))
                .accessibilityIdentifier("command.\(action.0)")
        }
    }
}
