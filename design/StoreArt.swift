// MedBeam App Store artwork: screenshots, product page header, search results image.
// Run:  swift design/StoreArt.swift            (reads design/raw, writes design/appstore)
import AppKit

// MARK: - Palette (from the app icon)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func ns(_ c: CGColor) -> NSColor { NSColor(cgColor: c)! }

let navyInk = rgb(0x0E1A33)     // headline text
let navy = rgb(0x1E4A8A)
let gold = rgb(0xFFC53D)
let green = rgb(0x34C759), red = rgb(0xFF3B30), orange = rgb(0xFF9500), blue = rgb(0x0A84FF)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let rawDir = "design/raw", outDir = "design/appstore"

func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = f.fontDescriptor.withDesign(.rounded), let r = NSFont(descriptor: d, size: size) { return r }
    return f
}

func makeContext(_ w: CGFloat, _ h: CGFloat) -> CGContext {
    let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!   // App Store art must be opaque
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    return ctx
}

func save(_ ctx: CGContext, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("wrote \(outDir)/\(name).png  \(ctx.width)x\(ctx.height)")
}

func loadShot(_ name: String) -> CGImage {
    NSImage(contentsOfFile: "\(rawDir)/\(name).png")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

// MARK: - Background: soft pastel gradient, a sweeping gold band, sparkles and dots

struct Rng { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 33) / Double(1 << 31) } }

func background(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat, seed: UInt64, colors: [UInt32], avoid: CGRect = .null) {
    let g = CGGradient(colorsSpace: space, colors: colors.map { rgb($0) } as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])

    // Sweeping band (like a beam of light) across the lower middle
    let u = min(w, h)
    for (offset, alpha, width) in [(0.0, 0.55, 0.16), (0.07, 0.30, 0.05)] {
        let path = CGMutablePath()
        let y0 = h * (0.42 - offset)
        path.move(to: CGPoint(x: -0.1 * w, y: y0))
        path.addCurve(to: CGPoint(x: 1.1 * w, y: y0 + h * 0.10),
                      control1: CGPoint(x: 0.35 * w, y: y0 + h * 0.20), control2: CGPoint(x: 0.65 * w, y: y0 - h * 0.12))
        ctx.addPath(path)
        ctx.setStrokeColor(rgb(0xFFC53D, alpha))
        ctx.setLineWidth(u * width)
        ctx.setLineCap(.round)
        ctx.strokePath()
    }

    var r = Rng(s: seed)
    let dotColors: [UInt32] = [0xFF6B8A, 0xFFB020, 0x0A84FF, 0x34C759, 0xFF8A3D]
    func spot() -> CGPoint {
        for _ in 0..<50 {
            let c = CGPoint(x: r.next() * w, y: r.next() * h)
            if !avoid.contains(c) { return c }
        }
        return CGPoint(x: w * 0.95, y: h * 0.05)
    }
    for _ in 0..<9 {
        let c = spot()
        let d = u * (0.018 + r.next() * 0.018)
        ctx.setFillColor(rgb(dotColors[Int(r.next() * 5) % 5], 0.9))
        ctx.fillEllipse(in: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
    }
    for _ in 0..<7 {
        sparkle(ctx, spot(), u * (0.025 + r.next() * 0.03),
                rgb([0xFFB020, 0x34C759, 0xFF6B8A, 0x0A84FF][Int(r.next() * 4) % 4], 0.9))
    }
}

func sparkle(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ color: CGColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
    ctx.addPath(p); ctx.setFillColor(color); ctx.fillPath()
}

// MARK: - Headline: line 1 plain, line 2 inside a gold highlight pill

func headline(_ ctx: CGContext, _ line1: String, _ line2: String, sub: String?, centerX: CGFloat, top: CGFloat,
              size: CGFloat, align: NSTextAlignment = .center, maxWidth: CGFloat) {
    let a1 = NSAttributedString(string: line1, attributes: [.font: font(size, .black), .foregroundColor: ns(navyInk), .kern: -size * 0.02])
    let a2 = NSAttributedString(string: line2, attributes: [.font: font(size, .black), .foregroundColor: ns(navyInk), .kern: -size * 0.02])
    let s1 = a1.size(), s2 = a2.size()
    let lineH = size * 1.12
    func x(_ width: CGFloat) -> CGFloat { align == .center ? centerX - width / 2 : centerX }

    a1.draw(at: CGPoint(x: x(s1.width), y: top - lineH))
    let padX = size * 0.28, padY = size * 0.06
    let pill = CGRect(x: x(s2.width) - padX, y: top - lineH * 2 - padY - size * 0.02, width: s2.width + padX * 2, height: lineH + padY * 1.4)
    ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pill.height * 0.32, cornerHeight: pill.height * 0.32, transform: nil))
    ctx.setFillColor(gold); ctx.fillPath()
    a2.draw(at: CGPoint(x: x(s2.width), y: top - lineH * 2))

    if let sub {
        let para = NSMutableParagraphStyle(); para.alignment = align; para.lineSpacing = size * 0.06
        let a3 = NSAttributedString(string: sub, attributes: [.font: font(size * 0.36, .semibold),
                                                               .foregroundColor: ns(rgb(0x0E1A33, 0.72)), .paragraphStyle: para])
        let rect = CGRect(x: align == .center ? centerX - maxWidth / 2 : centerX, y: top - lineH * 2 - size * 1.25,
                          width: maxWidth, height: size * 0.95)
        a3.draw(in: rect)
    }
}

// MARK: - Phone: dark rounded bezel around a real screenshot, tilted, with a soft shadow

func phone(_ ctx: CGContext, _ shot: CGImage, center: CGPoint, width: CGFloat, angle: CGFloat) {
    let screenW = width * 0.94
    let screenH = screenW * CGFloat(shot.height) / CGFloat(shot.width)
    let bezel = (width - screenW) / 2
    let body = CGRect(x: -width / 2, y: -(screenH + bezel * 2) / 2, width: width, height: screenH + bezel * 2)
    let screen = body.insetBy(dx: bezel, dy: bezel)
    let radius = width * 0.135

    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    ctx.setShadow(offset: CGSize(width: 0, height: -width * 0.03), blur: width * 0.08, color: rgb(0x0E1A33, 0.35))
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(rgb(0x111214)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    // thin metal edge
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: width * 0.004, dy: width * 0.004), cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setStrokeColor(rgb(0x5A5E66, 0.9)); ctx.setLineWidth(width * 0.006); ctx.strokePath()
    // screen
    let sr = radius - bezel
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: sr, cornerHeight: sr, transform: nil))
    ctx.clip()
    ctx.draw(shot, in: screen)
    ctx.restoreGState()
}

// MARK: - Floating callout chip: white capsule, colored dot or icon, bold text, optional badge

func chip(_ ctx: CGContext, _ text: String, center: CGPoint, size: CGFloat, dot: CGColor? = nil,
          symbol: String? = nil, symbolColor: CGColor = navy, badge: String? = nil, badgeColor: CGColor = gold, angle: CGFloat = 0) {
    let label = NSAttributedString(string: text, attributes: [.font: font(size, .heavy), .foregroundColor: ns(navyInk)])
    let ls = label.size()
    let badgeAttr = badge.map { NSAttributedString(string: $0, attributes: [.font: font(size * 0.95, .heavy), .foregroundColor: ns(navyInk)]) }
    let bs = badgeAttr?.size() ?? .zero
    var symbolImage: NSImage?
    if dot == nil, let symbol, let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size * 1.0, weight: .bold)) {
        symbolImage = NSImage(size: img.size, flipped: false) { r in
            img.draw(in: r); ns(symbolColor).set(); r.fill(using: .sourceAtop); return true
        }
    }
    let lead = dot != nil ? size * 1.5 : (symbolImage.map { $0.size.width + size * 0.5 } ?? 0)
    let h = size * 2.1
    let w = size * 0.95 + lead + ls.width + (badgeAttr != nil ? bs.width + size * 1.7 : 0) + size * 0.95

    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.25), blur: size * 0.9, color: rgb(0x0E1A33, 0.22))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
    ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    var x = rect.minX + size * 0.95
    if let dot {
        let d = size * 0.62
        ctx.setFillColor(dot); ctx.fillEllipse(in: CGRect(x: x, y: -d / 2, width: d, height: d))
        x += lead
    } else if let tinted = symbolImage {
        let s = tinted.size
        tinted.draw(in: CGRect(x: x, y: -s.height / 2, width: s.width, height: s.height))
        x += lead
    }
    label.draw(at: CGPoint(x: x, y: -ls.height / 2 - size * 0.04))
    x += ls.width + size * 0.6
    if let badgeAttr {
        let br = CGRect(x: x, y: -size * 0.78, width: bs.width + size * 1.0, height: size * 1.56)
        ctx.addPath(CGPath(roundedRect: br, cornerWidth: br.height / 2, cornerHeight: br.height / 2, transform: nil))
        ctx.setFillColor(badgeColor); ctx.fillPath()
        badgeAttr.draw(at: CGPoint(x: br.minX + size * 0.5, y: -bs.height / 2 - size * 0.04))
    }
    ctx.restoreGState()
}

// MARK: - Screenshots (1206 x 2622, "iPhone with Dynamic Island (medium display)")

struct Chip { let text: String; let x: CGFloat; let y: CGFloat; var dot: CGColor? = nil; var symbol: String? = nil
              var symbolColor: CGColor = navy; var badge: String? = nil; var badgeColor: CGColor = gold; var angle: CGFloat = 0 }
struct Slide { let name: String; let shot: String; let l1: String; let l2: String; let sub: String
               let colors: [UInt32]; let angle: CGFloat; let chips: [Chip] }

let W: CGFloat = 1206, H: CGFloat = 2622
let slides: [Slide] = [
    Slide(name: "1-find", shot: "2-map", l1: "Find your meds", l2: "before you drive.",
          sub: "See which pharmacies near you are most likely to have it.",
          colors: [0xFFF4D6, 0xFFE9DC, 0xDCEBFF], angle: -3,
          chips: [Chip(text: "Ted Pharmacy", x: 330, y: 1500, dot: green, badge: "66%", badgeColor: rgb(0xD7F5DD), angle: -4),
                  Chip(text: "FDA shortage", x: 870, y: 1170, dot: red, angle: 3),
                  Chip(text: "19 pharmacies nearby", x: 560, y: 520, symbol: "mappin.and.ellipse", angle: -2)]),
    Slide(name: "2-odds", shot: "3-card", l1: "Know your odds", l2: "at every pharmacy.",
          sub: "A clear percentage, and exactly why.",
          colors: [0xE4F0FF, 0xFFF4D6, 0xFFE3E0], angle: 3,
          chips: [Chip(text: "Very common", x: 300, y: 1260, symbol: "arrow.up.circle.fill", symbolColor: green, angle: -3),
                  Chip(text: "FDA shortage", x: 880, y: 1000, symbol: "arrow.down.circle.fill", symbolColor: orange, angle: 4),
                  Chip(text: "Controlled", x: 330, y: 700, symbol: "arrow.down.circle.fill", symbolColor: orange, angle: -2)]),
    Slide(name: "3-shortages", shot: "4-risk", l1: "Spot shortages", l2: "early.",
          sub: "Live data from the FDA and Medicaid, in one score.",
          colors: [0xFFEBD9, 0xFFF6DA, 0xE2F4E8], angle: -3,
          chips: [Chip(text: "Supply risk", x: 330, y: 1450, dot: orange, badge: "Elevated", badgeColor: rgb(0xFFE2B8), angle: -4),
                  Chip(text: "4 of 10 makers short", x: 760, y: 1080, dot: red, angle: 3),
                  Chip(text: "5 public data sources", x: 520, y: 560, symbol: "building.columns.fill", angle: -2)]),
    Slide(name: "4-neighbors", shot: "6-report", l1: "Help your", l2: "neighbors.",
          sub: "Tap “had it” or “didn’t.” It makes every estimate better.",
          colors: [0xE2F4E8, 0xFFF4D6, 0xFFE3E0], angle: 3,
          chips: [Chip(text: "Takes 5 seconds", x: 330, y: 1650, symbol: "hand.tap.fill", angle: -3),
                  Chip(text: "Anonymous", x: 880, y: 1330, symbol: "lock.fill", symbolColor: green, angle: 4),
                  Chip(text: "Helps everyone nearby", x: 560, y: 540, symbol: "person.3.fill", angle: -2)]),
    Slide(name: "5-watch", shot: "5-favorites", l1: "Watch your", l2: "medications.",
          sub: "Save your meds and see shortage status at a glance.",
          colors: [0xDCEBFF, 0xEDE4FF, 0xFFF4D6], angle: -3,
          chips: [Chip(text: "Live FDA data", x: 330, y: 1420, dot: green, angle: -4),
                  Chip(text: "Adderall 20 mg", x: 850, y: 1110, dot: red, badge: "Shortage", badgeColor: rgb(0xFFD9D6), angle: 3),
                  Chip(text: "One tap to search again", x: 540, y: 560, symbol: "star.fill", symbolColor: gold, angle: -2)]),
    Slide(name: "6-private", shot: "1-home", l1: "Private", l2: "by design.",
          sub: "Free. No account, no prescription details, no GPS tracking.",
          colors: [0xFFF4D6, 0xDCEBFF, 0xE2F4E8], angle: 3,
          chips: [Chip(text: "No account", x: 300, y: 1560, symbol: "person.crop.circle.badge.xmark", symbolColor: green, angle: -4),
                  Chip(text: "No GPS tracking", x: 860, y: 1250, symbol: "location.slash.fill", symbolColor: green, angle: 3),
                  Chip(text: "Always free", x: 330, y: 760, symbol: "gift.fill", symbolColor: green, angle: -2)]),
]

try? FileManager.default.removeItem(atPath: outDir)
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (i, s) in slides.enumerated() {
    let ctx = makeContext(W, H)
    background(ctx, W, H, seed: UInt64(i + 3) * 7919, colors: s.colors, avoid: CGRect(x: 0, y: H - 640, width: W, height: 640))
    headline(ctx, s.l1, s.l2, sub: s.sub, centerX: W / 2, top: H - 150, size: 112, maxWidth: W - 160)
    // Phone bleeds off the bottom, like a real product shot
    phone(ctx, loadShot(s.shot), center: CGPoint(x: W / 2, y: 930), width: 920, angle: s.angle)
    for c in s.chips {
        chip(ctx, c.text, center: CGPoint(x: c.x, y: c.y + 110), size: 46, dot: c.dot, symbol: c.symbol,
             symbolColor: c.symbolColor, badge: c.badge, badgeColor: c.badgeColor, angle: c.angle)
    }
    save(ctx, s.name)
}

// MARK: - Product page header (3840 x 1646, 21:9)

do {
    let w: CGFloat = 3840, h: CGFloat = 1646
    let ctx = makeContext(w, h)
    background(ctx, w, h, seed: 42, colors: [0xFFF4D6, 0xFFE9DC, 0xDCEBFF], avoid: CGRect(x: 180, y: 300, width: 2000, height: 1250))
    headline(ctx, "Find your meds", "before you drive.", sub: "Free. Official FDA and Medicaid data. Anonymous.",
             centerX: 300, top: h - 330, size: 200, align: .left, maxWidth: 1900)
    phone(ctx, loadShot("4-risk"), center: CGPoint(x: 2450, y: 560), width: 640, angle: -6)
    phone(ctx, loadShot("3-card"), center: CGPoint(x: 3230, y: 540), width: 640, angle: 6)
    phone(ctx, loadShot("2-map"), center: CGPoint(x: 2840, y: 700), width: 700, angle: 0)
    chip(ctx, "Ted Pharmacy", center: CGPoint(x: 2300, y: 1150), size: 62, dot: green, badge: "66%", badgeColor: rgb(0xD7F5DD), angle: -4)
    chip(ctx, "FDA shortage", center: CGPoint(x: 3330, y: 1250), size: 62, dot: red, angle: 4)
    save(ctx, "header-3840x1646")
}

// MARK: - Search results artwork (2880 x 1920, 3:2)

do {
    let w: CGFloat = 2880, h: CGFloat = 1920
    let ctx = makeContext(w, h)
    background(ctx, w, h, seed: 77, colors: [0xFFF4D6, 0xFFE9DC, 0xDCEBFF], avoid: CGRect(x: 0, y: h - 560, width: w, height: 560))
    headline(ctx, "Find your meds", "before you drive.", sub: nil, centerX: w / 2, top: h - 110, size: 170, maxWidth: w)
    phone(ctx, loadShot("3-card"), center: CGPoint(x: 700, y: 520), width: 640, angle: -7)
    phone(ctx, loadShot("4-risk"), center: CGPoint(x: 2180, y: 520), width: 640, angle: 7)
    phone(ctx, loadShot("2-map"), center: CGPoint(x: w / 2, y: 470), width: 720, angle: 0)
    chip(ctx, "FDA shortage", center: CGPoint(x: 600, y: 1240), size: 60, dot: red, angle: -4)
    chip(ctx, "Ted Pharmacy", center: CGPoint(x: 2300, y: 1250), size: 60, dot: green, badge: "66%", badgeColor: rgb(0xD7F5DD), angle: 4)
    save(ctx, "search-2880x1920")
}
