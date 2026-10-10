// Frames raw simulator screenshots for the App Store.
// Run:  swift design/ScreenshotFramer.swift design/raw design/appstore [width height]
// App Store Connect's "iPhone with Dynamic Island (medium display)" slot takes 1206 x 2622.
import AppKit

let args = CommandLine.arguments
let W: CGFloat = args.count > 4 ? CGFloat(Double(args[3])!) : 1206
let H: CGFloat = args.count > 4 ? CGFloat(Double(args[4])!) : 2622
let scale = W / 1284
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
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: W, y: H), startRadius: 0, endCenter: CGPoint(x: W, y: H), endRadius: 1100 * scale, options: [])

    // Headline + subtitle
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let title = NSAttributedString(string: text.0, attributes: [.font: NSFont.systemFont(ofSize: 96 * scale, weight: .bold),
                                                                 .foregroundColor: NSColor.white, .paragraphStyle: para])
    let sub = NSAttributedString(string: text.1, attributes: [.font: NSFont.systemFont(ofSize: 58 * scale, weight: .medium),
                                                               .foregroundColor: NSColor(calibratedRed: 1, green: 0.8, blue: 0.35, alpha: 1), .paragraphStyle: para])
    title.draw(in: CGRect(x: 60 * scale, y: H - 330 * scale, width: W - 120 * scale, height: 140 * scale))
    sub.draw(in: CGRect(x: 60 * scale, y: H - 430 * scale, width: W - 120 * scale, height: 80 * scale))

    // Phone screenshot with rounded corners and a soft shadow
    let shotW: CGFloat = 1010 * scale, shotH = shotW * CGFloat(shot.height) / CGFloat(shot.width)
    let rect = CGRect(x: (W - shotW) / 2, y: H - 520 * scale - shotH, width: shotW, height: shotH)
    let path = CGPath(roundedRect: rect, cornerWidth: 96 * scale, cornerHeight: 96 * scale, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 60 * scale, color: color(0, 0, 0, 0.55))
    ctx.addPath(path); ctx.setFillColor(color(0, 0, 0)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.clip(); ctx.draw(shot, in: rect); ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(color(1, 1, 1, 0.18)); ctx.setLineWidth(4); ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("wrote \(outDir)/\(name).png")
}
