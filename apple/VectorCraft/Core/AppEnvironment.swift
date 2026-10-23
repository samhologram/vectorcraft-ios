import Foundation
import UIKit
@preconcurrency import VectorCraftKit

/// Process-wide one-time setup.
enum AppEnvironment {
    private static let once: Void = {
        AppSettings.prepare()
        // iOS has no font folders the engine knows: add the system fonts and the app's own font directory.
        let appFonts = Bundle.main.resourceURL?.appendingPathComponent("Fonts").path
        configureFonts(appFontDir: appFonts.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil })
    }()

    /// Idempotent; safe to call from every scene.
    static func bootstrap() { _ = once }
}
