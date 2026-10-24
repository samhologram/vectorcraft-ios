import Foundation

/// Typed access to user settings and launch arguments.
enum AppSettings {
    enum Key {
        static let pencilOnly = "pencilOnly"
        static let inspectorVisible = "inspectorVisible"
        static let panelGroups = "panelGroups.v1"
    }

    static let demoArgument = "-VectorCraftDemo"
    static let resetArgument = "-VectorCraftResetSettings"

    /// `-VectorCraftDemo`: a new document is seeded through engine commands.
    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains(demoArgument) }

    /// Launched by a UI test (or asked to start from clean settings).
    static var shouldResetSettings: Bool {
        let info = ProcessInfo.processInfo
        return info.arguments.contains(resetArgument) || info.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Call once at launch: resets persisted settings for test runs, then registers defaults.
    static func prepare() {
        let defaults = UserDefaults.standard
        if shouldResetSettings {
            defaults.removeObject(forKey: Key.pencilOnly)
            defaults.removeObject(forKey: Key.inspectorVisible)
            defaults.removeObject(forKey: Key.panelGroups)
        }
        defaults.register(defaults: [Key.pencilOnly: false, Key.inspectorVisible: true])
    }

    /// "Only Draw with Apple Pencil": fingers pan instead of drawing.
    static var pencilOnly: Bool {
        get { UserDefaults.standard.bool(forKey: Key.pencilOnly) }
        set { UserDefaults.standard.set(newValue, forKey: Key.pencilOnly) }
    }

    static var inspectorVisible: Bool {
        get { UserDefaults.standard.object(forKey: Key.inspectorVisible) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.inspectorVisible) }
    }

    static var panelGroups: [PanelGroup] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Key.panelGroups),
                  let groups = try? JSONDecoder().decode([PanelGroup].self, from: data) else {
                return [PanelGroup(tabs: ["properties", "color", "stroke"]),
                        PanelGroup(tabs: ["layers", "artboards"])]
            }
            return groups
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: Key.panelGroups)
        }
    }
}
