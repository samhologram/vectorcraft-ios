import SwiftUI
import VectorCraftKit

/// One toolbar group: shows the group's current tool and, when the group has more tools, a flyout.
/// `popover` (iPad): tap selects; a second tap or a long press opens the flyout.
/// Otherwise (iPhone strip): tap selects, a long press opens a menu.
struct ToolGroupButton: View {
    let model: DocumentModel
    let group: ToolGroupInfo
    var edge: CGFloat = 44
    var showsLabel = false
    var usesPopover = true

    @Environment(EditorUIState.self) private var ui
    @State private var flyout = false

    private var key: String { group.tools.first?.id ?? "" }

    var body: some View {
        if let tool = ui.currentTool(in: group, active: model.activeTool) {
            let selected = group.tools.contains { $0.id == model.activeTool }
            let multi = group.tools.count > 1
            Group {
                if usesPopover || !multi {
                    Button {
                        if selected && multi { flyout = true } else { model.selectTool(tool.id) }
                    } label: { label(tool, multi: multi) }
                    .glassToggle(selected)
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in if multi { flyout = true } })
                    .popover(isPresented: $flyout, arrowEdge: .leading) { flyoutList }
                } else {
                    Menu {
                        flyoutItems
                    } label: { label(tool, multi: multi) } primaryAction: {
                        model.selectTool(tool.id)
                    }
                    .menuStyle(.button)
                    .glassToggle(selected)
                }
            }
            .accessibilityLabel(tool.label)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("toolGroup.\(key)")
        }
    }

    private func label(_ tool: ToolInfo, multi: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: CommandCatalog.shared.symbol(forTool: tool.id))
                .font(edge < 40 ? .body : .title3)
                .frame(width: edge, height: edge)
                .overlay(alignment: .bottomTrailing) {
                    if multi {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(-45))
                            .padding(3)
                    }
                }
            if showsLabel {
                Text(verbatim: tool.label).font(.caption2).lineLimit(1)
            }
        }
        .frame(minWidth: showsLabel ? 58 : nil)
    }

    @ViewBuilder
    private var flyoutItems: some View {
        ForEach(group.tools, id: \.id) { t in
            Button {
                flyout = false
                model.selectTool(t.id)
            } label: {
                Label(t.label, systemImage: CommandCatalog.shared.symbol(forTool: t.id))
            }
            .accessibilityIdentifier("tool.\(t.id)")
        }
    }

    private var flyoutList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(group.tools, id: \.id) { t in
                Button {
                    flyout = false
                    model.selectTool(t.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: CommandCatalog.shared.symbol(forTool: t.id)).frame(width: 24)
                        Text(verbatim: t.label).lineLimit(1)
                        Spacer(minLength: 12)
                        if let sc = t.shortcut {
                            Text(verbatim: sc).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        if t.id == model.activeTool { Image(systemName: "checkmark") }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tool.\(t.id)")
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 220)
        .presentationCompactAdaptation(.popover)
    }
}
