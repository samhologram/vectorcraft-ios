import CryptoKit
import Foundation

/// App-owned destination for editable copies. iCloud is used only when the signed app has its container.
enum VectorCloudContainer {
    static let identifier = "iCloud.ca.hologram.vectorcraft"

    static func documentsFolder() -> URL {
        let fm = FileManager.default
        if let root = fm.url(forUbiquityContainerIdentifier: identifier) {
            let documents = root.appending(path: "Documents", directoryHint: .isDirectory)
            try? fm.createDirectory(at: documents, withIntermediateDirectories: true)
            return documents
        }
        return URL.documentsDirectory
    }

    /// A copy created while offline stays the same copy if iCloud becomes available later.
    static func existingFolders() -> [URL] {
        let local = URL.documentsDirectory
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: identifier) else { return [local] }
        return [root.appending(path: "Documents", directoryHint: .isDirectory), local]
    }

    static func prepare() {
        Task.detached(priority: .utility) {
            guard let root = FileManager.default.url(forUbiquityContainerIdentifier: identifier) else { return }
            try? FileManager.default.createDirectory(
                at: root.appending(path: "Documents", directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
    }
}

/// ReadConfiguration has the original's name and bytes, but no source URL. Their digest identifies the same
/// foreign file on a later open without tying a copy to a temporary DocumentManager URL.
enum VectorNativeCopyMap {
    private static let defaultsKey = "vectorcraftNativeCopies.v1"
    private static let lock = NSLock()

    static func key(name: String, data: Data) -> String {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "\(name)|\(data.count)|\(hash)"
    }

    private static func load() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    static func existingCopy(for key: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard let stored = load()[key] else { return nil }
        let folders: [URL]
        let file: String
        if stored.hasPrefix("local:") {
            folders = [URL.documentsDirectory]
            file = String(stored.dropFirst("local:".count))
        } else if stored.hasPrefix("cloud:") {
            folders = VectorCloudContainer.existingFolders().filter { $0 != URL.documentsDirectory }
            file = String(stored.dropFirst("cloud:".count))
        } else {
            folders = VectorCloudContainer.existingFolders() // earlier map format
            file = stored
        }
        return folders.map { $0.appending(path: file) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func remember(_ url: URL, for key: String) {
        lock.lock(); defer { lock.unlock() }
        var map = load()
        let location = url.deletingLastPathComponent().standardizedFileURL == URL.documentsDirectory.standardizedFileURL
            ? "local:" : "cloud:"
        map[key] = location + url.lastPathComponent
        if let data = try? JSONEncoder().encode(map) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }
}
