import Foundation

/// One independently collapsible row of tabs in the iPad inspector.
struct PanelGroup: Codable, Identifiable, Equatable {
    var id: UUID
    var tabs: [String]
    var selected: String
    var collapsed: Bool

    init(tabs: [String], selected: String? = nil, collapsed: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.tabs = tabs
        self.selected = selected ?? tabs.first ?? "properties"
        self.collapsed = collapsed
    }
}

extension DocumentModel {
    /// Toolbar and Window menu share one visibility route; closing never removes a tab or changes its layout.
    func togglePanelVisibility() {
        if narrowPanelLayout {
            phoneSheetPresented.toggle()
        } else {
            inspectorVisible.toggle()
            if inspectorVisible { revealCurrentDockPanel() }
        }
    }

    private func revealCurrentDockPanel() {
        let shown = lastShownPanel.flatMap { id in
            panelGroups.contains(where: { $0.tabs.contains(id) }) ? id : nil
        } ?? panelGroups.first?.selected
        guard let shown else { return }
        lastShownPanel = shown
        panelRevealRevision += 1
    }

    /// Selecting an existing tab still bumps this token, so scroll readers reveal it again.
    func showDockPanel(_ id: String) {
        guard CommandCatalog.shared.panels.contains(where: { $0.id == id }) else { return }
        if let index = panelGroups.firstIndex(where: { $0.tabs.contains(id) }) {
            panelGroups[index].selected = id
            panelGroups[index].collapsed = false
        } else {
            panelGroups.append(PanelGroup(tabs: [id]))
        }
        if let dedicated = Panel.from(panelID: id) {
            activePanel = dedicated
            activeGenericPanel = nil
        } else {
            activeGenericPanel = id
        }
        lastShownPanel = id
        panelRevealRevision += 1
        if narrowPanelLayout { phoneSheetPresented = true } else { inspectorVisible = true }
        persistPanelGroups()
    }

    func hideDockPanel(_ id: String) {
        guard let index = panelGroups.firstIndex(where: { $0.tabs.contains(id) }) else { return }
        panelGroups[index].tabs.removeAll { $0 == id }
        if panelGroups[index].tabs.isEmpty {
            panelGroups.remove(at: index)
        } else if panelGroups[index].selected == id {
            panelGroups[index].selected = panelGroups[index].tabs[0]
        }
        persistPanelGroups()
    }

    func toggleDockGroup(_ id: UUID) {
        guard let index = panelGroups.firstIndex(where: { $0.id == id }) else { return }
        panelGroups[index].collapsed.toggle()
        persistPanelGroups()
    }

    func moveDockGroup(_ id: UUID, by delta: Int) {
        guard let index = panelGroups.firstIndex(where: { $0.id == id }) else { return }
        let next = index + delta
        guard panelGroups.indices.contains(next) else { return }
        panelGroups.swapAt(index, next)
        persistPanelGroups()
    }

    func moveDockTab(_ id: String, toGroup target: UUID) {
        guard let source = panelGroups.firstIndex(where: { $0.tabs.contains(id) }),
              let destination = panelGroups.firstIndex(where: { $0.id == target }), source != destination else { return }
        panelGroups[source].tabs.removeAll { $0 == id }
        if panelGroups[source].tabs.isEmpty {
            panelGroups.remove(at: source)
        } else if panelGroups[source].selected == id {
            panelGroups[source].selected = panelGroups[source].tabs[0]
        }
        guard let updatedDestination = panelGroups.firstIndex(where: { $0.id == target }) else { return }
        panelGroups[updatedDestination].tabs.append(id)
        showDockPanel(id)
    }

    func persistPanelGroups() { AppSettings.panelGroups = panelGroups }
}
