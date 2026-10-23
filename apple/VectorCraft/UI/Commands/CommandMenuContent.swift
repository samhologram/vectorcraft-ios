import SwiftUI
import VectorCraftKit

/// Renders one desktop menu section (File, Edit, Object…) as SwiftUI menu content. The tree comes from the desktop
/// layout (`MenuLayout`, filtered for this platform): commands, separators and submenus. Use inside a `Menu`.
struct CommandMenuContent: View {
    let model: DocumentModel
    let title: String

    var body: some View {
        // Reading the revision makes the enabled states follow the document.
        let _ = model.state.revision
        MenuNodes(model: model, nodes: MenuLayout.nodes(for: title), path: title)
    }
}

private struct MenuNodes: View {
    let model: DocumentModel
    let nodes: [MenuNode]
    let path: String

    var body: some View {
        ForEach(nodes) { node in
            switch node.kind {
            case .separator:
                Divider()
            case .submenu(let label, let children):
                Menu(label) {
                    MenuNodes(model: model, nodes: children, path: path + "." + label)
                }
                .accessibilityIdentifier("menu.\(path).\(label)")
            case .command(let id, let params, let accessibilityID):
                Button(node.label) { model.present(id, params: params) }
                    .disabled(!model.isEnabled(id))
                    .accessibilityIdentifier(accessibilityID)
            }
        }
    }
}
