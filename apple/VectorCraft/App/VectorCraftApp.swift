import SwiftUI

@main
struct VectorCraftApp: App {
    init() {
        AppEnvironment.bootstrap()
        VectorCloudContainer.prepare()
    }

    var body: some Scene {
        // A document app: the system browser (Files) opens and creates documents; every window hosts one.
        DocumentGroup(newDocument: { VectorCraftDocument() }) { file in
            EditorRootView(model: file.document.model)
        }
        .commands {
            // File / Edit / Object / Type / Select / Effect / View / Window / Help, from the desktop menu layout.
            EditorCommands()
        }

        DocumentGroupLaunchScene("VectorCraft") {
            NewDocumentButton("New Drawing")
            NewFromPhotoButton()
        } background: {
            Color(.systemBackground)
        } overlayAccessoryView: { geometry in
            // The app icon above the title, laid out from the title's frame.
            let side = min(max(geometry.titleViewFrame.height * 1.2, 72), 128)
            Image("LaunchIcon")
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
                .position(x: geometry.titleViewFrame.midX,
                          y: geometry.titleViewFrame.minY - side / 2 - 16)
                .accessibilityHidden(true)
        }
    }
}
