import UIKit

/// Hidden first responder that shows the software keyboard while a Type tool is editing and forwards typed text
/// and backspace to the model. Hardware keyboards type into it too.
final class CanvasTextInput: UIView, UIKeyInput {
    var onInsert: ((String) -> Void)?
    var onDelete: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    // Always report text so backspace is delivered even with nothing "typed".
    var hasText: Bool { true }

    func insertText(_ text: String) { onInsert?(text) }
    func deleteBackward() { onDelete?() }

    // Plain typing: no autocorrection, capitalisation or smart punctuation (the engine owns the text).
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .default

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
    }

    required init?(coder: NSCoder) { nil }
}
