import UIKit
@preconcurrency import VectorCraftKit

/// Draws the tool overlays (marquee, path previews, anchors, handles, guides, labels) with Core Graphics in view
/// coordinates, mapping document points with the canvas' view transform. Passes touches through.
final class CanvasOverlayView: UIView {
    private var items: [OverlayItem] = []
    private var viewTransform = ViewTransform()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { nil }

    func update(items: [OverlayItem], transform: ViewTransform) {
        self.items = items
        self.viewTransform = transform
        setNeedsDisplay()
    }

    private func color(_ raw: some Sequence<UInt8>, alphaScale: CGFloat = 1) -> UIColor {
        let rgba = Array(raw)
        guard rgba.count >= 3 else { return .systemBlue }
        let a = rgba.count >= 4 ? CGFloat(rgba[3]) / 255 : 1
        return UIColor(red: CGFloat(rgba[0]) / 255, green: CGFloat(rgba[1]) / 255, blue: CGFloat(rgba[2]) / 255,
                       alpha: a * alphaScale)
    }

    private func point(_ pts: [Double], _ i: Int) -> CGPoint? {
        guard i >= 0, i + 1 < pts.count, pts[i].isFinite, pts[i + 1].isFinite else { return nil }
        return viewTransform.toView(CGPoint(x: pts[i], y: pts[i + 1]))
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let dash: [CGFloat] = [5, 4]
        for item in items {
            let stroke = color(item.rgba)
            let lineWidth = max(CGFloat(item.width), 1)
            ctx.saveGState()
            defer { ctx.restoreGState() }
            ctx.setLineWidth(lineWidth)
            ctx.setStrokeColor(stroke.cgColor)
            if item.dashed { ctx.setLineDash(phase: 0, lengths: dash) }
            switch item.kind {
            case "marquee":
                guard let a = point(item.points, 0), let b = point(item.points, 2) else { continue }
                let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                ctx.setFillColor(color(item.rgba, alphaScale: 0.12).cgColor)
                ctx.fill(r)
                ctx.setLineWidth(1)
                ctx.setLineDash(phase: 0, lengths: dash)
                ctx.stroke(r)
            case "path":
                var started = false
                var last: CGPoint?
                ctx.beginPath()
                var i = 0
                while i + 1 < item.points.count {
                    let x = item.points[i], y = item.points[i + 1]
                    if x.isNaN || y.isNaN {
                        started = false
                    } else if let p = point(item.points, i) {
                        if started { ctx.addLine(to: p) } else { ctx.move(to: p); started = true }
                        last = p
                    }
                    i += 2
                }
                _ = last
                if item.filled {
                    ctx.setFillColor(color(item.rgba, alphaScale: 0.25).cgColor)
                    ctx.drawPath(using: .fillStroke)
                } else {
                    ctx.strokePath()
                }
            case "line":
                guard let a = point(item.points, 0), let b = point(item.points, 2) else { continue }
                ctx.setLineWidth(1)
                ctx.move(to: a)
                ctx.addLine(to: b)
                ctx.strokePath()
            case "distance":
                guard let a = point(item.points, 0), let b = point(item.points, 2), !item.text.isEmpty else { continue }
                let dx = b.x - a.x
                let dy = b.y - a.y
                let length = hypot(dx, dy)
                guard length > 0 else { continue }
                let nx = -dy / length * 4
                let ny = dx / length * 4
                ctx.setLineWidth(1)
                ctx.move(to: a)
                ctx.addLine(to: b)
                for end in [a, b] {
                    ctx.move(to: CGPoint(x: end.x - nx, y: end.y - ny))
                    ctx.addLine(to: CGPoint(x: end.x + nx, y: end.y + ny))
                }
                ctx.strokePath()
                drawPill(item.text, at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2),
                         background: stroke, ctx: ctx)
            case "gridLine":
                guard let a = point(item.points, 0), let b = point(item.points, 2) else { continue }
                ctx.setLineWidth(1)
                ctx.move(to: a)
                ctx.addLine(to: b)
                ctx.strokePath()
            case "anchor":
                guard let p = point(item.points, 0) else { continue }
                let s = max(CGFloat(item.size), 7) * 1.25
                let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
                ctx.setLineWidth(1.5)
                ctx.setFillColor((item.filled ? stroke : UIColor.white).cgColor)
                ctx.fill(r)
                ctx.stroke(r)
            case "curvePoint":
                guard let p = point(item.points, 0) else { continue }
                let s = max(CGFloat(item.size), 7) * 1.25
                let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
                ctx.setLineWidth(1.5)
                ctx.setFillColor((item.filled ? stroke : UIColor.white).cgColor)
                ctx.fillEllipse(in: r)
                ctx.strokeEllipse(in: r)
            case "handle":
                guard let p = point(item.points, 0) else { continue }
                let s: CGFloat = 8
                let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
                ctx.setLineWidth(1.5)
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fillEllipse(in: r)
                ctx.strokeEllipse(in: r)
            case "highlight":
                guard item.points.count >= 8, let p0 = point(item.points, 0) else { continue }
                ctx.setFillColor(color(item.rgba).cgColor)
                ctx.move(to: p0)
                for k in 1..<4 { if let p = point(item.points, k * 2) { ctx.addLine(to: p) } }
                ctx.closePath()
                ctx.fillPath()
            case "swatch":
                guard let p = point(item.points, 0) else { continue }
                let s: CGFloat = 16
                let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
                ctx.setFillColor(color(item.rgba).cgColor)
                ctx.fill(r)
                ctx.setStrokeColor(UIColor.white.cgColor)
                ctx.setLineWidth(item.filled ? 3 : 1.5)
                ctx.stroke(r)
                ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.6).cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(r.insetBy(dx: -1.5, dy: -1.5))
            case "label", "measure":
                guard let p = point(item.points, 0), !item.text.isEmpty else { continue }
                drawPill(item.text, at: CGPoint(x: p.x + 10, y: p.y + 10),
                         background: item.kind == "measure" ? UIColor(white: 0.15, alpha: 0.88) : stroke,
                         ctx: ctx)
            default:
                continue
            }
        }
    }

    private func drawPill(_ text: String, at origin: CGPoint, background: UIColor, ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let box = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 6)
        ctx.setFillColor(background.cgColor)
        ctx.addPath(UIBezierPath(roundedRect: box, cornerRadius: 6).cgPath)
        ctx.fillPath()
        (text as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attrs)
    }
}
