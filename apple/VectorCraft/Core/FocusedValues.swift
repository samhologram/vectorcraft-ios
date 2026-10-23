import SwiftUI

private struct DocumentModelKey: FocusedValueKey {
    typealias Value = DocumentModel
}

extension FocusedValues {
    /// The model of the focused document scene; read by the menu bar (`EditorCommands`).
    var documentModel: DocumentModel? {
        get { self[DocumentModelKey.self] }
        set { self[DocumentModelKey.self] = newValue }
    }
}
