import SwiftUI
import VectorCraftKit

/// A slider whose drag is one undo step: `begin` on touch down, `change` while moving (a preview), `end` on release.
/// Label left, value right; VoiceOver adjusts in steps.
struct DragSlider: View {
    let identifier: String
    let label: String
    let range: ClosedRange<Double>
    let value: Double
    var step: Double = 0
    var decimals = 0
    var unit = ""
    var onBegin: () -> Void = {}
    var onChange: (Double) -> Void
    var onEnd: () -> Void = {}

    @State private var dragValue: Double?
    @State private var active = false

    private var shown: Double { min(range.upperBound, max(range.lowerBound, dragValue ?? value)) }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(verbatim: label).font(.subheadline).lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: String(format: "%.\(decimals)f", shown) + unit)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Slider(
                value: Binding(
                    get: { shown },
                    set: { v in
                        let snapped = step > 0 ? (v / step).rounded() * step : v
                        if !active { active = true; onBegin() }
                        dragValue = snapped
                        onChange(snapped)
                    }
                ),
                in: range
            ) { editing in
                if !editing && active {
                    active = false
                    onEnd()
                    dragValue = nil
                }
            }
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
        }
    }
}

/// Numeric field that applies on Return / when focus leaves.
struct NumberField: View {
    let identifier: String
    let label: String
    let value: Double
    var unit = ""
    var enabled = true
    var onCommit: (Double) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private func format(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let r = (v * 100).rounded() / 100
        return r == r.rounded() && abs(r) < 1e15 ? String(Int(r)) : String(r)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: label).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            TextField(label, text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(commit)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
            if !unit.isEmpty { Text(verbatim: unit).font(.caption).foregroundStyle(.secondary) }
        }
        .disabled(!enabled)
        .onAppear { text = format(value) }
        .onChange(of: value) { _, new in if !focused { text = format(new) } }
        .onChange(of: focused) { _, now in if !now { commit() } }
    }

    private func commit() {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")), v.isFinite else { text = format(value); return }
        if abs(v - value) > 0.0001 { onCommit(v) }
        text = format(v)
    }
}

/// A button that runs one catalog command (`command.<id>`), greyed while the engine says it cannot run.
struct CommandButton: View {
    let model: DocumentModel
    let id: String
    let title: String
    var symbol: String?
    var params: [String: Any] = [:]
    var identifier: String?
    
    var body: some View {
        Button {
            model.present(id, params: params)
        } label: {
            if let symbol {
                Label { Text(verbatim: title).lineLimit(1) } icon: { Image(systemName: symbol) }
            } else {
                Text(verbatim: title).lineLimit(1)
            }
        }
        .disabled(!model.isEnabled(id))
        .accessibilityIdentifier(identifier ?? "command.\(id)")
    }
}

/// Icon-only command button with a text fallback label for accessibility.
struct CommandIconButton: View {
    let model: DocumentModel
    let id: String
    let title: String
    let symbol: String
    var params: [String: Any] = [:]
    var identifier: String?
    
    var body: some View {
        Button {
            model.present(id, params: params)
        } label: {
            Image(systemName: symbol).frame(minWidth: 28, minHeight: 24)
        }
        .buttonStyle(.glass)
        .disabled(!model.isEnabled(id))
        .accessibilityLabel(title)
        .help(title)
        .accessibilityIdentifier(identifier ?? "command.\(id)")
    }
}

/// One paint (hex / none / mixed / gradient / pattern) drawn as a small chip. The colours are the document's own
/// paint values (and the conventional red slash for "none"), not UI chrome.
struct PaintChip: View {
    let paint: String?
    var size: CGFloat = 28
    var ring = false

    var body: some View {
        ZStack {
            if let p = paint, let c = Color(vcHex: p) {
                shape.fill(c)
            } else if paint == "gradient" {
                // Stand-in: the engine reports only that the paint is a gradient, not its stops.
                shape.fill(LinearGradient(colors: [.white, .gray, .black], startPoint: .leading, endPoint: .trailing))
            } else if paint == "pattern" {
                shape.fill(.secondary.opacity(0.4))
                Image(systemName: "square.grid.2x2").font(.system(size: size * 0.45)).foregroundStyle(.secondary)
            } else if paint == "mixed" {
                shape.fill(.secondary.opacity(0.25))
                Image(systemName: "ellipsis").foregroundStyle(.secondary)
            } else {
                shape.fill(.clear)
                Path { p in
                    p.move(to: CGPoint(x: size * 0.15, y: size * 0.85))
                    p.addLine(to: CGPoint(x: size * 0.85, y: size * 0.15))
                }
                .stroke(.red, lineWidth: 2)
                .frame(width: size, height: size)
            }
            shape.stroke(.primary.opacity(0.35), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var shape: some Shape { RoundedRectangle(cornerRadius: ring ? size / 2 : 6, style: .continuous) }
}

extension DocumentModel {
    /// The fill the wells show: the selection's, or the toolbar default when nothing is selected.
    var effectiveFill: String? { selection.count > 0 ? selection.fill : state.fillDefault }
    var effectiveStroke: String? { selection.count > 0 ? selection.stroke : state.strokeDefault }
}

/// Fill and stroke colour wells with swap and default buttons. Tapping a well opens the Color panel for that paint.
struct FillStrokeWells: View {
    let model: DocumentModel
    var compact = false
    @Environment(EditorUIState.self) private var ui
    
    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            well(.fill, paint: model.effectiveFill, id: "control.properties.fill", title: "Fill")
            well(.stroke, paint: model.effectiveStroke, id: "control.properties.stroke", title: "Stroke")
            if !compact {
                VStack(spacing: 4) {
                    CommandIconButton(model: model, id: "paint.swap", title: "Swap Fill and Stroke", symbol: "arrow.left.arrow.right")
                    CommandIconButton(model: model, id: "paint.default", title: "Default Fill and Stroke", symbol: "square.on.square.dashed")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func well(_ target: EditorUIState.PaintTarget, paint: String?, id: String, title: String) -> some View {
        Button {
            ui.paintTarget = target
            model.showPanel(named: "color")
        } label: {
            VStack(spacing: 2) {
                PaintChip(paint: paint, size: compact ? 26 : 34, ring: target == .stroke)
                if !compact { Text(verbatim: title).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            .padding(compact ? 2 : 4)
            .overlay {
                if ui.paintTarget == target {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}

/// Section header used by the inspector pages.
struct PanelEmpty: View {
    let title: String
    let symbol: String
    let message: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}

/// Apply a system colour to the fill or stroke: one undo step per burst of changes (the picker streams values).
@MainActor
final class ColorStreamer {
    private var open = false
    private var task: Task<Void, Never>?

    func send(_ model: DocumentModel, target: EditorUIState.PaintTarget, hex: String) {
        let id = target == .fill ? "paint.setFill" : "paint.setStroke"
        if !open { open = true; model.beginDrag("Set Color") }
        model.preview(id, ["color": hex])
        task?.cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.open = false
            model.endDrag()
        }
    }
}
