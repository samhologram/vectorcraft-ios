import Foundation
import CoreGraphics
@preconcurrency import VectorCraftKit

/// The canvas view state. Mapping (same as the desktop canvas): `view = T(w/2, h/2) · S(zoom) · T(-center)`,
/// document coordinates are y-down, so the inverse is a plain scale and offset.
struct ViewTransform: Equatable, Sendable {
    static let minZoom = 0.01
    static let maxZoom = 512.0

    var centerX: Double = 540
    var centerY: Double = 540
    /// View points per document point (1 = 100 %).
    var zoom: Double = 1
    var viewSize: CGSize = .zero
    var pixelScale: Double = 2
    var outline = false
    var smartGuides = true
    var snapToGrid = false
    var snapToPoint = false
    var showBBox = true
    var artboard: UInt32 = 0

    /// True once the canvas has a real size (before that nothing can be fitted).
    var hasSize: Bool { viewSize.width > 1 && viewSize.height > 1 }

    func viewParams(pixelScale override: Double? = nil) -> ViewParams {
        ViewParams(
            centerX: centerX, centerY: centerY, zoom: zoom,
            width: Double(viewSize.width), height: Double(viewSize.height),
            pixelScale: override ?? pixelScale,
            outline: outline, smartGuides: smartGuides, snapToGrid: snapToGrid, snapToPoint: snapToPoint,
            showBbox: showBBox, artboard: artboard)
    }

    /// Document point -> view point.
    func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: viewSize.width / 2 + (Double(p.x) - centerX) * zoom,
                y: viewSize.height / 2 + (Double(p.y) - centerY) * zoom)
    }

    /// View point -> document point.
    func toDocument(_ p: CGPoint) -> CGPoint {
        guard zoom > 0 else { return CGPoint(x: centerX, y: centerY) }
        return CGPoint(x: centerX + (Double(p.x) - Double(viewSize.width) / 2) / zoom,
                       y: centerY + (Double(p.y) - Double(viewSize.height) / 2) / zoom)
    }

    static func clampedZoom(_ z: Double) -> Double {
        guard z.isFinite else { return 1 }
        return min(max(z, minZoom), maxZoom)
    }
}
