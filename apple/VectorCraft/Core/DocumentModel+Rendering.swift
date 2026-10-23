import SwiftUI
import CoreGraphics
@preconcurrency import VectorCraftKit

/// RGBA8 premultiplied pixels from the engine. Plain `Sendable` data, so it can cross actors;
/// `CGImage` is not `Sendable` and is only built on the main actor.
struct PixelBuffer: Sendable {
    let width: Int
    let height: Int
    let data: Data

    init?(_ image: RenderedImage) {
        let w = Int(image.width), h = Int(image.height)
        guard w > 0, h > 0, w <= 16384, h <= 16384, image.rgba.count >= w * h * 4 else { return nil }
        width = w
        height = h
        data = Data(image.rgba)
    }

    /// Wraps the bytes without copying them (the data provider keeps the `Data` alive).
    func makeCGImage() -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
            intent: .defaultIntent)
    }
}

/// A rendered canvas image and the view it was rendered for, so the canvas can place it correctly while the
/// view keeps moving (pinch, pan) until a fresh render arrives.
struct RenderedFrame {
    let image: CGImage
    let centerX: Double
    let centerY: Double
    let zoom: Double
    let size: CGSize
}

extension DocumentModel {
    /// Renders the current view off the main actor. `draft` renders at half resolution (during gestures).
    func renderFrame(draft: Bool) async -> RenderedFrame? {
        guard view.hasSize else { return nil }
        let snapshot = view
        let params = snapshot.viewParams(pixelScale: snapshot.pixelScale * (draft ? 0.5 : 1))
        let handle = self.handle
        let pixels: PixelBuffer? = await Task.detached(priority: draft ? .userInitiated : .utility) {
            guard let image = try? handle.render(view: params) else { return nil }
            return PixelBuffer(image)
        }.value
        guard !Task.isCancelled, let image = pixels?.makeCGImage() else { return nil }
        return RenderedFrame(image: image, centerX: snapshot.centerX, centerY: snapshot.centerY,
                             zoom: snapshot.zoom, size: snapshot.viewSize)
    }

    /// The current view as an image, rendered on a background task.
    func renderImage() async -> CGImage? {
        await renderFrame(draft: false)?.image
    }

    /// Thumbnail of artboard `index` with the long edge `edge` pixels.
    func artboardThumbnail(_ index: Int, edge: Int) async -> CGImage? {
        guard index >= 0 else { return nil }
        let handle = self.handle
        let i = UInt32(index), e = UInt32(min(max(edge, 16), 4096))
        let pixels: PixelBuffer? = await Task.detached(priority: .utility) {
            guard let image = try? handle.renderArtboard(index: i, maxEdge: e) else { return nil }
            return PixelBuffer(image)
        }.value
        guard !Task.isCancelled else { return nil }
        return pixels?.makeCGImage()
    }

    /// Export bytes ("svg" | "pdf" | "png"; options: scale, artboard, transparent). Runs off the main actor.
    func exportData(format: String, options: [String: Any] = [:]) async throws -> Data {
        let json = Self.encode(options) ?? "{}"
        let handle = self.handle
        return try await Task.detached(priority: .userInitiated) {
            try handle.export(format: format, optionsJson: json)
        }.value
    }
}
