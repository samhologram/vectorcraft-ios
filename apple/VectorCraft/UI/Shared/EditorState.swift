import SwiftUI
import UIKit
import VectorCraftKit

/// UI-side state shared by the iPad and iPhone layouts: which paint the colour pages edit, the tool each group
/// button shows, and whether the inspector lives in a sheet. Panels and commands go through `DocumentModel`.
@MainActor @Observable
final class EditorUIState {
    /// Which paint the Color / Swatches / Gradient panels edit.
    enum PaintTarget: String, CaseIterable { case fill, stroke }
    var paintTarget: PaintTarget = .fill
    /// The inspector is shown as a sheet (iPhone, or a window narrower than 700 pt).
    var narrow = false

    /// The tool each group's button shows: the last one chosen in the group.
    var remembered: [String: String] = [:]

    /// The tool a group button shows and runs: the active tool when it is in the group, else the group's last one.
    func currentTool(in group: ToolGroupInfo, active: String) -> ToolInfo? {
        if let t = group.tools.first(where: { $0.id == active }) { return t }
        if let key = group.tools.first?.id, let id = remembered[key], let t = group.tools.first(where: { $0.id == id }) { return t }
        return group.tools.first
    }

    func noteActiveTool(_ tool: String) {
        for g in CommandCatalog.shared.toolGroups {
            if let key = g.tools.first?.id, g.tools.contains(where: { $0.id == tool }) { remembered[key] = tool }
        }
    }
}

func jsonObject(_ text: String) -> [String: Any] {
    guard let data = text.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return obj
}

func jsonNumber(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }
func jsonString(_ any: Any?) -> String? { any as? String }
func jsonBool(_ any: Any?) -> Bool? { (any as? NSNumber)?.boolValue }

// MARK: Colours

extension Color {
    /// "#rrggbb" to a colour; nil when it is not a hex colour ("none", "mixed", "gradient"...).
    init?(vcHex hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// "#rrggbb" in sRGB.
    var vcHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ x: CGFloat) -> Int { Int((max(0, min(1, x)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(r), byte(g), byte(b))
    }
}

// MARK: Shortcuts

struct ParsedShortcut {
    let key: KeyEquivalent
    let modifiers: EventModifiers
}

/// Parses the engine's egui notation ("V", "Shift+C", "Cmd+Shift+]") into a SwiftUI shortcut; nil when unusable.
func parseShortcut(_ text: String?) -> ParsedShortcut? {
    guard let text, !text.isEmpty else { return nil }
    var mods: EventModifiers = []
    var keyPart = ""
    let parts = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    for (i, part) in parts.enumerated() {
        switch part.lowercased() {
        case "cmd", "command", "ctrl", "control": mods.insert(.command)
        case "shift": mods.insert(.shift)
        case "alt", "option": mods.insert(.option)
        case "": if i == parts.count - 1 { keyPart = "+" }
        default: keyPart = part
        }
    }
    guard keyPart.count == 1, let ch = keyPart.lowercased().first else { return nil }
    return ParsedShortcut(key: KeyEquivalent(ch), modifiers: mods)
}

// MARK: Shared modifiers

/// Glass button style that is prominent while `selected`.
struct GlassToggleStyle: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        if selected {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

extension View {
    func glassToggle(_ selected: Bool) -> some View { modifier(GlassToggleStyle(selected: selected)) }
}

/// Engine reads used by the panels (decoded JSON, nil on failure).
extension DocumentModel {
    /// A read for panel data: failures (nothing selected, no document yet…) stay silent instead of raising the error alert.
    @discardableResult
    func quietQuery(_ id: String, _ params: [String: Any] = [:]) -> Any? {
        let before = lastError
        let result = query(id, params)
        lastError = before
        return result
    }

    /// `document.node` of the first selected object.
    func firstSelectedNode() -> [String: Any]? {
        guard let id = selection.ids.first else { return nil }
        return quietQuery("document.node", ["id": id]) as? [String: Any]
    }
}
