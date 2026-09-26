import Cocoa
import SwiftUI

/// The patchbay mark: a lowercase "p" drawn as patch-bay hardware. The bowl is a jack
/// socket (ring and contact), the stem is the cord hanging out of it, curling off at the
/// foot. One geometry, three renderings: a template image for the menu bar, a SwiftUI
/// shape for the popover header, and the full-colour app icon.
enum Logo {
    /// 18 pt menu-bar template, rendered at 2x. `alert` cuts a notch into the top-right
    /// and sets a dot in it, so the badge survives template tinting.
    static func statusImage(alert: Bool) -> NSImage {
        let image = render(pixels: 36, points: 18) { ctx, s in
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(Geometry.markPath(size: s, stroke: Geometry.menuStroke))
            ctx.fillPath()
            if alert {
                let c = CGPoint(x: 0.86 * s, y: 0.15 * s)
                ctx.setBlendMode(.clear)
                ctx.fillEllipse(in: CGRect(x: c.x - 0.2 * s, y: c.y - 0.2 * s, width: 0.4 * s, height: 0.4 * s))
                ctx.setBlendMode(.normal)
                ctx.fillEllipse(in: CGRect(x: c.x - 0.12 * s, y: c.y - 0.12 * s, width: 0.24 * s, height: 0.24 * s))
            }
        }
        image.isTemplate = true
        image.accessibilityDescription = "patchbay"
        return image
    }

    /// macOS app icon at `size` pixels (square, with the standard transparent margin).
    static func appIcon(size: CGFloat) -> NSImage {
        let px = max(16, Int(size.rounded()))
        return render(pixels: px, points: CGFloat(px)) { ctx, s in drawIcon(ctx, s) }
    }

    /// Header mark; fills its frame, coloured by the caller's foregroundStyle.
    struct Mark: View {
        init() {}
        var body: some View {
            MarkShape().aspectRatio(1, contentMode: .fit)
        }
    }

    private struct MarkShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height)
            var p = Path(Geometry.markPath(size: s, stroke: Geometry.menuStroke))
            p = p.applying(CGAffineTransform(translationX: rect.midX - s / 2, y: rect.midY - s / 2))
            return p
        }
    }
}

// MARK: - Geometry

/// Unit-square coordinates, y down. Optically centred: the bowl is heavier than the stem,
/// so the ring sits a touch right of centre.
private enum Geometry {
    static let center = CGPoint(x: 0.535, y: 0.38)
    static let radius: CGFloat = 0.275
    static let contact: CGFloat = 0.085
    /// Stem runs down the bowl's left edge, then the cord swings out to the right.
    static var stemX: CGFloat { center.x - radius }
    static let stemBottom: CGFloat = 0.72
    static let foot = CGPoint(x: 0.47, y: 0.905)
    /// ≈1.7 pt at 18 pt: the menu-bar stroke weight Apple's own symbols sit at.
    static let menuStroke: CGFloat = 0.094

    static func ring(_ s: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: (center.x - radius) * s, y: (center.y - radius) * s, width: 2 * radius * s, height: 2 * radius * s), transform: nil)
    }

    static func cord(_ s: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: stemX * s, y: center.y * s))
        p.addLine(to: CGPoint(x: stemX * s, y: stemBottom * s))
        p.addQuadCurve(to: CGPoint(x: foot.x * s, y: foot.y * s), control: CGPoint(x: stemX * s, y: foot.y * s))
        return p
    }

    static func contactDot(_ s: CGFloat, radius r: CGFloat = contact) -> CGPath {
        CGPath(ellipseIn: CGRect(x: (center.x - r) * s, y: (center.y - r) * s, width: 2 * r * s, height: 2 * r * s), transform: nil)
    }

    /// The whole mark as filled outlines (nonzero winding; overlaps are the same colour).
    static func markPath(size s: CGFloat, stroke: CGFloat) -> CGPath {
        let w = stroke * s
        let ring = ring(s).copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 1)
        let cord = cord(s).copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 1)
        let p = CGMutablePath()
        p.addPath(ring); p.addPath(cord); p.addPath(contactDot(s))
        return p
    }
}

// MARK: - Rendering

private extension Logo {
    /// Draws into an exact-size bitmap with a y-down context.
    static func render(pixels: Int, points: CGFloat, _ draw: (CGContext, CGFloat) -> Void) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: points, height: points)
        NSGraphicsContext.saveGraphicsState()
        let gc = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = gc
        let ctx = gc.cgContext
        // The context already maps points to the rep's pixels; only flip to y-down.
        ctx.translateBy(x: 0, y: points)
        ctx.scaleBy(x: 1, y: -1)
        draw(ctx, points)
        gc.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: points, height: points))
        image.addRepresentation(rep)
        return image
    }

    static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    static func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    }

    /// Big Sur grid: 824/1024 body, 185/1024 corner, soft drop shadow. A dark anodised
    /// panel with a faint row of neighbouring sockets, the mark as a metal jack with an
    /// amber cord and a lit contact.
    static func drawIcon(_ ctx: CGContext, _ s: CGFloat) {
        let body = CGRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
        let corner = s * 185 / 1024
        let shape = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)

        // Drop shadow.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: s * 10 / 1024), blur: s * 28 / 1024, color: rgb(0x000000, 0.45))
        ctx.addPath(shape); ctx.setFillColor(rgb(0x1E1C1A)); ctx.fillPath()
        ctx.restoreGState()

        // Panel: warm charcoal, lighter at the top, with a faint amber bloom behind the jack.
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        ctx.drawLinearGradient(gradient([rgb(0x36322D), rgb(0x201E1B)], [0, 1]),
                               start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
        // Mark area: the mark's unit square mapped onto the middle of the panel.
        let m = s * 0.56
        let origin = CGPoint(x: (s - m) / 2 + s * 0.012, y: (s - m) / 2 + s * 0.035)
        let jack = CGPoint(x: origin.x + Geometry.center.x * m, y: origin.y + Geometry.center.y * m)
        ctx.drawRadialGradient(gradient([rgb(0xDBA85C, 0.13), rgb(0xDBA85C, 0)], [0, 1]),
                               startCenter: jack, startRadius: 0, endCenter: jack, endRadius: s * 0.36, options: [])

        ctx.restoreGState()

        // Top-edge highlight.
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        ctx.addPath(CGPath(roundedRect: body.insetBy(dx: s * 0.002, dy: s * 0.002), cornerWidth: corner, cornerHeight: corner, transform: nil))
        ctx.setLineWidth(s * 0.004)
        ctx.replacePathWithStrokedPath(); ctx.clip()
        ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0.0)], [0, 0.5]),
                               start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        let w = Geometry.menuStroke * 1.05 * m

        // Cord: amber, round-capped, with a soft shadow; drawn first so the socket sits on top.
        let cord = Geometry.cord(m).copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 1)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: m * 0.02), blur: m * 0.04, color: rgb(0x000000, 0.5))
        ctx.addPath(cord); ctx.setFillColor(rgb(0xC98F40)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(cord); ctx.clip()
        ctx.drawLinearGradient(gradient([rgb(0xF0C47C), rgb(0xD69F52), rgb(0xB57E35)], [0, 0.45, 1]),
                               start: CGPoint(x: Geometry.stemX * m - w / 2, y: 0), end: CGPoint(x: Geometry.stemX * m + w / 2, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()

        // Socket hole.
        let holeRadius = Geometry.radius - Geometry.menuStroke * 0.62
        ctx.addPath(Geometry.contactDot(m, radius: holeRadius)); ctx.setFillColor(rgb(0x121110)); ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(Geometry.contactDot(m, radius: holeRadius)); ctx.clip()
        let c = CGPoint(x: Geometry.center.x * m, y: Geometry.center.y * m)
        ctx.drawRadialGradient(gradient([rgb(0x000000, 0), rgb(0x000000, 0.6)], [0.6, 1]),
                               startCenter: c, startRadius: 0, endCenter: c, endRadius: holeRadius * m, options: [])
        ctx.restoreGState()

        // Metal ring: brushed, lit from above, with a thin dark bevel inside.
        let ring = Geometry.ring(m).copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 1)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: m * 0.02), blur: m * 0.05, color: rgb(0x000000, 0.55))
        ctx.addPath(ring); ctx.setFillColor(rgb(0x9A938A)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(ring); ctx.clip()
        let top = (Geometry.center.y - Geometry.radius) * m - w / 2, bottom = (Geometry.center.y + Geometry.radius) * m + w / 2
        ctx.drawLinearGradient(gradient([rgb(0xF3ECE1), rgb(0xE2D9CB), rgb(0xC4BAAB), rgb(0xD3CABC)], [0, 0.4, 0.8, 1]),
                               start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
        ctx.restoreGState()

        // Lit contact.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: m * 0.05, color: rgb(0xF2B864, 0.6))
        ctx.addPath(Geometry.contactDot(m)); ctx.setFillColor(rgb(0xE9B466)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(Geometry.contactDot(m)); ctx.clip()
        let cr = Geometry.contact * m
        ctx.drawRadialGradient(gradient([rgb(0xFFE7B8), rgb(0xE3A955)], [0, 1]),
                               startCenter: CGPoint(x: c.x - cr * 0.3, y: c.y - cr * 0.35), startRadius: 0, endCenter: c, endRadius: cr, options: [])
        ctx.restoreGState()
        ctx.restoreGState()
    }
}
