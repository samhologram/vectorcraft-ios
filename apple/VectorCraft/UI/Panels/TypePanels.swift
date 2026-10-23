import SwiftUI
import VectorCraftKit

/// Character: font, size, leading, tracking, kerning, scale, baseline, case and line styles for the selected type
/// (or the characters selected with the Type tool).
struct CharacterPanel: View {
    let model: DocumentModel

    @State private var family = "Font"
    @State private var style = ""
    @State private var styles: [String] = []
    @State private var size = 24.0
    @State private var leading = 0.0
    @State private var tracking = 0.0
    @State private var kerning = 0.0
    @State private var hScale = 100.0
    @State private var vScale = 100.0
    @State private var baseline = 0.0
    @State private var fontPicker = false
    @State private var flags: Set<String> = []
    @State private var position = "normal"

    var body: some View {
        Form {
            Section {
                Button {
                    fontPicker = true
                } label: {
                    HStack {
                        Text("Font")
                        Spacer()
                        Text(verbatim: family).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .accessibilityIdentifier("control.character.font")
                if styles.count > 1 {
                    Picker("Style", selection: Binding(get: { style }, set: { style = $0; model.run("text.setStyle", ["style": $0]) })) {
                        ForEach(styles, id: \.self) { Text(verbatim: $0).tag($0) }
                    }
                    .accessibilityIdentifier("control.character.style")
                }
                HStack(spacing: 10) {
                    NumberField(identifier: "control.character.size", label: "Size", value: size, unit: "pt") { size = $0; model.run("text.setStyle", ["size": max(1, $0)]) }
                    HStack(spacing: 4) {
                        CommandIconButton(model: model, id: "type.size.decrease", title: "Smaller", symbol: "minus")
                        CommandIconButton(model: model, id: "type.size.increase", title: "Larger", symbol: "plus")
                    }
                }
                NumberField(identifier: "control.character.leading", label: "Leading", value: leading, unit: "pt") { leading = $0; model.run("text.setStyle", ["leading": max(0, $0)]) }
                Button("Auto Leading") { model.run("text.setStyle", ["leading": "auto"]) }
                    .accessibilityIdentifier("control.character.autoLeading")
                NumberField(identifier: "control.character.tracking", label: "Tracking", value: tracking) { tracking = $0; model.run("text.setStyle", ["tracking": $0]) }
                NumberField(identifier: "control.character.kerning", label: "Kerning", value: kerning) { kerning = $0; model.run("text.setFormat", ["kerning": $0]) }
            }
            Section("Scale and Baseline") {
                NumberField(identifier: "control.character.hScale", label: "Horizontal", value: hScale, unit: "%") { hScale = $0; model.run("text.setFormat", ["hScale": $0]) }
                NumberField(identifier: "control.character.vScale", label: "Vertical", value: vScale, unit: "%") { vScale = $0; model.run("text.setFormat", ["vScale": $0]) }
                NumberField(identifier: "control.character.baseline", label: "Baseline", value: baseline, unit: "pt") { baseline = $0; model.run("text.setFormat", ["baselineShift": $0]) }
            }
            Section("Case and Lines") {
                HStack(spacing: 8) {
                    flag("All Caps", "textformat.size.larger", "allCaps")
                    flag("Small Caps", "textformat.size.smaller", "smallCaps")
                    flag("Underline", "underline", "underline")
                    flag("Strikethrough", "strikethrough", "strikethrough")
                }
                Picker("Position", selection: Binding(get: { position }, set: { position = $0; model.run("text.setFormat", ["position": $0]) })) {
                    Text("Normal").tag("normal")
                    Text("Superscript").tag("superscript")
                    Text("Subscript").tag("subscript")
                }
                .accessibilityIdentifier("control.character.position")
            }
            Section {
                CommandButton(model: model, id: "type.createOutlines", title: "Create Outlines", symbol: "textformat")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $fontPicker) {
            FontPicker(model: model, current: family) { chosen in
                family = chosen
                model.run("text.setStyle", ["font": chosen])
                loadStyles()
            }
        }
        .task { loadStyles() }
        .accessibilityIdentifier("control.character")
    }

    private func flag(_ title: String, _ symbol: String, _ key: String) -> some View {
        let on = flags.contains(key)
        return Button {
            // The engine does not report character flags, so the panel tracks what it set and toggles.
            if on { flags.remove(key) } else { flags.insert(key) }
            model.run("text.setFormat", [key: !on])
        } label: { Image(systemName: symbol).frame(minWidth: 28, minHeight: 24) }
        .glassToggle(on)
        .accessibilityLabel(title)
        .accessibilityIdentifier("control.character.\(key)")
    }

    private func loadStyles() {
        guard family != "Font",
              let out = model.quietQuery("text.fontList", ["family": family]) as? [String: Any],
              let s = out["styles"] as? [String] else { return }
        styles = s
        if !s.contains(style) { style = s.first ?? "" }
    }
}

/// Searchable family list (`text.fontList`).
struct FontPicker: View {
    let model: DocumentModel
    let current: String
    let choose: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var families: [String] = []
    @State private var query = ""

    private var shown: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? families : families.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(shown, id: \.self) { f in
                Button {
                    choose(f)
                    dismiss()
                } label: {
                    HStack {
                        Text(verbatim: f).font(.custom(f, size: 17)).foregroundStyle(.primary)
                        Spacer()
                        if f == current { Image(systemName: "checkmark") }
                    }
                }
                .accessibilityIdentifier("control.character.family.\(f)")
            }
            .searchable(text: $query, prompt: "Search fonts")
            .navigationTitle("Font")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .overlay {
                if families.isEmpty { ProgressView() }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            if let out = model.quietQuery("text.fontList") as? [String: Any], let f = out["families"] as? [String] { families = f }
        }
    }
}

/// Paragraph: alignment, indents, spacing, hyphenation.
struct ParagraphPanel: View {
    let model: DocumentModel

    @State private var justify = "left"
    @State private var leftIndent = 0.0
    @State private var rightIndent = 0.0
    @State private var firstLine = 0.0
    @State private var before = 0.0
    @State private var after = 0.0
    @State private var hyphenate = false

    var body: some View {
        Form {
            Section("Alignment") {
                Picker("Align", selection: Binding(get: { justify }, set: { justify = $0; model.run("text.setStyle", ["justify": $0]) })) {
                    Image(systemName: "text.alignleft").tag("left")
                    Image(systemName: "text.aligncenter").tag("center")
                    Image(systemName: "text.alignright").tag("right")
                    Image(systemName: "text.justify").tag("justifyAll")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("control.paragraph.align")
            }
            Section("Indents") {
                NumberField(identifier: "control.paragraph.leftIndent", label: "Left", value: leftIndent, unit: "pt") { leftIndent = $0; model.run("text.setFormat", ["leftIndent": $0]) }
                NumberField(identifier: "control.paragraph.rightIndent", label: "Right", value: rightIndent, unit: "pt") { rightIndent = $0; model.run("text.setFormat", ["rightIndent": $0]) }
                NumberField(identifier: "control.paragraph.firstLineIndent", label: "First Line", value: firstLine, unit: "pt") { firstLine = $0; model.run("text.setFormat", ["firstLineIndent": $0]) }
            }
            Section("Spacing") {
                NumberField(identifier: "control.paragraph.spaceBefore", label: "Before", value: before, unit: "pt") { before = $0; model.run("text.setFormat", ["spaceBefore": $0]) }
                NumberField(identifier: "control.paragraph.spaceAfter", label: "After", value: after, unit: "pt") { after = $0; model.run("text.setFormat", ["spaceAfter": $0]) }
            }
            Section {
                Toggle("Hyphenate", isOn: Binding(get: { hyphenate }, set: { hyphenate = $0; model.run("text.setFormat", ["hyphenate": $0]) }))
                    .accessibilityIdentifier("control.paragraph.hyphenate")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("control.paragraph")
    }
}
