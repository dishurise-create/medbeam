// Frames raw simulator screenshots for the App Store (iPhone 6.5": 1284 x 2778).
// Run:  swift design/ScreenshotFramer.swift design/raw design/appstore
import AppKit

let W: CGFloat = 1284, H: CGFloat = 2778
let args = CommandLine.arguments
let inDir = args.count > 1 ? args[1] : "design/raw", outDir = args.count > 2 ? args[2] : "design/appstore"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let captions: [String: (String, String)] = [
    "1-home": ("Find your medication", "Search any prescription near you"),
    "2-map": ("Your odds, on a map", "Every nearby pharmacy, ranked"),
    "3-card": ("Know before you go", "A clear percentage, and why"),
    "4-risk": ("Spot shortages early", "Live FDA and Medicaid data"),
    "5-favorites": ("Watch your meds", "Shortage status at a glance"),
]

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
let space = CGColorSpace(name: CGColorSpace.sRGB)!

for (name, text) in captions.sorted(by: { $0.key < $1.key }) {
    guard let src = NSImage(contentsOfFile: "\(inDir)/\(name).png"),
          let shot = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("missing", name); continue }
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Background: navy night sky with a gold glow, like the app icon
    let bg = CGGradient(colorsSpace: space, colors: [color(0.055, 0.10, 0.20), color(0.12, 0.29, 0.54)] as CFArray, locations: nil)!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [color(1, 0.8, 0.35, 0.45), color(1, 0.8, 0.35, 0)] as CFArray, locations: nil)!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: W, y: H), startRadius: 0, endCenter: CGPoint(x: W, y: H), endRadius: 1100, options: [])

    // Headline + subtitle
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let title = NSAttributedString(string: text.0, attributes: [.font: NSFont.systemFont(ofSize: 96, weight: .bold),
                                                                 .foregroundColor: NSColor.white, .paragraphStyle: para])
    let sub = NSAttributedString(string: text.1, attributes: [.font: NSFont.systemFont(ofSize: 58, weight: .medium),
                                                               .foregroundColor: NSColor(calibratedRed: 1, green: 0.8, blue: 0.35, alpha: 1), .paragraphStyle: para])
    title.draw(in: CGRect(x: 60, y: H - 330, width: W - 120, height: 140))
    sub.draw(in: CGRect(x: 60, y: H - 430, width: W - 120, height: 80))

    // Phone screenshot with rounded corners and a soft shadow
    let shotW: CGFloat = 1010, shotH = shotW * CGFloat(shot.height) / CGFloat(shot.width)
    let rect = CGRect(x: (W - shotW) / 2, y: H - 520 - shotH, width: shotW, height: shotH)
    let path = CGPath(roundedRect: rect, cornerWidth: 96, cornerHeight: 96, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 60, color: color(0, 0, 0, 0.55))
    ctx.addPath(path); ctx.setFillColor(color(0, 0, 0)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.clip(); ctx.draw(shot, in: rect); ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(color(1, 1, 1, 0.18)); ctx.setLineWidth(4); ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("wrote \(outDir)/\(name).png")
}
