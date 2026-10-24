import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The photo is chosen before DocumentGroup receives a document. Cancelling throws, since returning nil would
/// make NewDocumentButton create an empty drawing.
struct NewFromPhotoButton: View {
    @State private var importer = VectorPhotoImporter()

    var body: some View {
        @Bindable var state = importer
        NewDocumentButton("New from Photo", for: VectorCraftDocument.self) { [importer] in
            try await importer.prepare()
        }
        .accessibilityIdentifier("newFromPhoto")
        .fullScreenCover(isPresented: $state.showsPicker, onDismiss: {
            importer.resolve(VectorPhotoProvider(nil))
        }) {
            VectorSystemPhotoPicker(importer: importer)
                .ignoresSafeArea()
        }
        .alert("Could not open the photo", isPresented: $state.failed) {
            Button("OK", role: .cancel) {}
        }
    }
}

private struct VectorPhotoProvider: @unchecked Sendable {
    let provider: NSItemProvider?
    init(_ provider: NSItemProvider?) { self.provider = provider }
}

@MainActor @Observable
private final class VectorPhotoImporter: NSObject, PHPickerViewControllerDelegate {
    var showsPicker = false
    var failed = false
    @ObservationIgnored private var continuation: CheckedContinuation<VectorPhotoProvider, Never>?

    func prepare() async throws -> VectorCraftDocument {
        resolve(VectorPhotoProvider(nil))
        let selected = await withCheckedContinuation { continuation in
            self.continuation = continuation
            showsPicker = true
        }
        guard let provider = selected.provider else { throw CancellationError() }
        do {
            guard let type = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .image) == true
            }) else { throw CocoaError(.fileReadUnknown) }
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                    if let data { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
                }
            }
            return try await Task.detached(priority: .userInitiated) {
                try VectorCraftDocument.fromPhoto(data)
            }.value
        } catch {
            failed = true
            throw CancellationError()
        }
    }

    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let selected = VectorPhotoProvider(results.first?.itemProvider)
        Task { @MainActor in
            showsPicker = false
            resolve(selected)
        }
    }

    func resolve(_ selected: VectorPhotoProvider) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: selected)
    }
}

private struct VectorSystemPhotoPicker: UIViewControllerRepresentable {
    let importer: VectorPhotoImporter

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = importer
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}
}
