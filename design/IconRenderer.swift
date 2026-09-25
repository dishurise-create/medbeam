// Draws the MedBeam app icon options as 1024×1024 PNGs.
// Run:  swift design/IconRenderer.swift design/out
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func linearGradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radialGradient(_ ctx: CGContext, _ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// Rounded "plus" cross centered at c.
func crossPath(center c: CGPoint, arm: CGFloat, thickness t: CGFloat, corner r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.addRoundedRect(in: CGRect(x: c.x - t / 2, y: c.y - arm, width: t, height: arm * 2), cornerWidth: r, cornerHeight: r)
    p.addRoundedRect(in: CGRect(x: c.x - arm, y: c.y - t / 2, width: arm * 2, height: t), cornerWidth: r, cornerHeight: r)
    return p
}

func render(_ name: String, draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!   // app icons must be opaque
    ctx.setShouldAntialias(true)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote", url.path)
}

// MARK: - Option A: "Beacon" — a map pin with a medical cross, sending out beams

render("icon-A-beacon") { ctx in
    // Deep teal → blue background
    linearGradient(ctx, [color(0x0FB9A6), color(0x0A58CA)], from: CGPoint(x: 0, y: size), to: CGPoint(x: size, y: 0))
    // Soft glow behind the pin
    radialGradient(ctx, [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)], center: CGPoint(x: 512, y: 590), radius: 420)

    // Beam arcs radiating above the pin (like a signal / lighthouse)
    ctx.setLineCap(.round)
    for (i, radius) in [250.0, 330.0, 410.0].enumerated() {
        ctx.setStrokeColor(color(0xFFFFFF, [0.55, 0.38, 0.22][i]))
        ctx.setLineWidth(34)
        ctx.addArc(center: CGPoint(x: 512, y: 610), radius: radius, startAngle: .pi * 0.28, endAngle: .pi * 0.72, clockwise: false)
        ctx.strokePath()
    }

    // Map pin (teardrop): circle + point, white with a soft shadow
    let pinCenter = CGPoint(x: 512, y: 560), r: CGFloat = 185
    let pin = CGMutablePath()
    pin.addArc(center: pinCenter, radius: r, startAngle: .pi * 1.18, endAngle: .pi * -0.18, clockwise: false)
    pin.addLine(to: CGPoint(x: 512, y: 215))
    pin.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0x032B5F, 0.45))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.addPath(pin); ctx.fillPath()
    ctx.restoreGState()

    // Cross inside the pin, in the brand gradient
    ctx.saveGState()
    ctx.addPath(crossPath(center: pinCenter, arm: 105, thickness: 78, corner: 22))
    ctx.clip()
    linearGradient(ctx, [color(0x12C8A8), color(0x0A5FD6)], from: CGPoint(x: 400, y: 660), to: CGPoint(x: 620, y: 460))
    ctx.restoreGState()
}

// MARK: - Option B: "Capsule beam" — a capsule shining a beam of light (MedBeam)

func drawCapsuleBeam(_ ctx: CGContext) {
    // Night-sky navy background
    linearGradient(ctx, [color(0x0E1A33), color(0x1E4A8A)], from: CGPoint(x: 0, y: 0), to: CGPoint(x: size, y: size))

    // Where the light comes out (the tip of the yellow half)
    let origin = CGPoint(x: 600, y: 600)

    // Beam: a cone opening toward the top-right corner, fading out
    ctx.saveGState()
    let beam = CGMutablePath()
    beam.move(to: CGPoint(x: origin.x - 30, y: origin.y + 40))
    beam.addLine(to: CGPoint(x: 700, y: 1100))
    beam.addLine(to: CGPoint(x: 1100, y: 1100))
    beam.addLine(to: CGPoint(x: 1100, y: 690))
    beam.addLine(to: CGPoint(x: origin.x + 40, y: origin.y - 30))
    beam.closeSubpath()
    ctx.addPath(beam)
    ctx.clip()
    linearGradient(ctx, [color(0xFFE9A6, 0.85), color(0xFFD45C, 0.35), color(0xFFD45C, 0.0)],
                   from: origin, to: CGPoint(x: 1024, y: 1024))
    ctx.restoreGState()

    // Soft glow where the beam starts
    radialGradient(ctx, [color(0xFFF1C1, 0.55), color(0xFFF1C1, 0)], center: origin, radius: 170)

    // Capsule tilted 45°, white half bottom-left, yellow half toward the light
    ctx.saveGState()
    ctx.translateBy(x: 440, y: 440)
    ctx.rotate(by: .pi / 4)
    let w: CGFloat = 600, h: CGFloat = 250
    let capsule = CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                         cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0x000000, 0.5))
    ctx.setFillColor(color(0xFFFFFF)); ctx.addPath(capsule); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(capsule); ctx.clip()
    ctx.setFillColor(color(0xFFC53D)); ctx.fill(CGRect(x: 0, y: -h, width: w, height: h * 2))
    // Seam between halves
    ctx.setFillColor(color(0xE0A423)); ctx.fill(CGRect(x: -6, y: -h, width: 12, height: h * 2))
    // Glossy highlight along the top
    ctx.setFillColor(color(0xFFFFFF, 0.38))
    ctx.addPath(CGPath(roundedRect: CGRect(x: -w / 2 + 50, y: h * 0.14, width: w - 100, height: h * 0.16),
                       cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()

    // Small sparkles in the beam
    func sparkle(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat) {
        let s = CGMutablePath()
        s.move(to: CGPoint(x: c.x, y: c.y + r))
        s.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
        s.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
        s.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
        s.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
        ctx.setFillColor(color(0xFFFFFF, a)); ctx.addPath(s); ctx.fillPath()
    }
    sparkle(CGPoint(x: 820, y: 860), 46, 0.95)
    sparkle(CGPoint(x: 900, y: 740), 26, 0.75)
    sparkle(CGPoint(x: 735, y: 950), 22, 0.6)
}

render("icon-B-capsule") { ctx in drawCapsuleBeam(ctx) }

// MARK: - Option C: "Radiant cross" — a medical cross with a sunburst of beams

render("icon-C-radiant") { ctx in
    linearGradient(ctx, [color(0xFF5A6E), color(0xFF9F43)], from: CGPoint(x: 0, y: 0), to: CGPoint(x: size, y: size))
    // Sunburst rays
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512)
    for i in 0..<16 {
        ctx.saveGState()
        ctx.rotate(by: CGFloat(i) * .pi / 8)
        let ray = CGMutablePath()
        ray.move(to: .zero)
        ray.addLine(to: CGPoint(x: -60, y: 760))
        ray.addLine(to: CGPoint(x: 60, y: 760))
        ray.closeSubpath()
        ctx.setFillColor(color(0xFFFFFF, i % 2 == 0 ? 0.16 : 0.08))
        ctx.addPath(ray); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.restoreGState()
    radialGradient(ctx, [color(0xFFFFFF, 0.35), color(0xFFFFFF, 0)], center: CGPoint(x: 512, y: 512), radius: 360)
    // Cross
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: color(0x8A1C2B, 0.45))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.addPath(crossPath(center: CGPoint(x: 512, y: 512), arm: 250, thickness: 180, corner: 48))
    ctx.fillPath()
    ctx.restoreGState()
}
