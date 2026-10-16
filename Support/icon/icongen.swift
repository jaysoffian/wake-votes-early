import Foundation
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Usage: swiftc -O icongen.swift -o icongen && ./icongen ../../App/Assets.xcassets/AppIcon.appiconset
// Draws the app icon from scratch: a yellow "WAKE VOTES EARLY" yard sign with a red arrow,
// modeled on the signs Wake County puts out in front of each site.
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let signYellow = CGColor(srgbRed: 0xF6/255, green: 0xF0/255, blue: 0x3A/255, alpha: 1)
let signRed = CGColor(srgbRed: 0xD6/255, green: 0x2A/255, blue: 0x2C/255, alpha: 1)

/// A line of text laid out with a heavy system font, with glyph-path bounds for exact centering.
struct TextLine {
    let line: CTLine
    let bounds: CGRect   // glyph bounds relative to the baseline origin

    init(_ text: String, fontSize: CGFloat) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy) as CTFont
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: signRed, .kern: fontSize * 0.02]
        line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    }

    func draw(in ctx: CGContext, centerX: CGFloat, baselineY: CGFloat) {
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: centerX - bounds.midX, y: baselineY)
        CTLineDraw(line, ctx)
    }
}

func drawSign(in ctx: CGContext, tile: CGRect) {
    ctx.setFillColor(signYellow)
    ctx.fill(tile)

    let w = tile.width
    let words = ["WAKE", "VOTES", "EARLY"]
    // Pick one font size so the widest word fills ~74% of the tile.
    let probe = words.map { TextLine($0, fontSize: 100) }
    let widest = probe.map(\.bounds.width).max()!
    let fontSize = 100 * (w * 0.74) / widest
    let lines = words.map { TextLine($0, fontSize: fontSize) }
    let capHeight = lines[0].bounds.height            // all caps, so every line is the same height
    let gap = capHeight * 0.26

    // Text block occupies the upper part of the tile; the arrow sits below it.
    let textTop = tile.maxY - w * 0.085
    var baseline = textTop - capHeight
    for line in lines {
        line.draw(in: ctx, centerX: tile.midX, baselineY: baseline)
        baseline -= capHeight + gap
    }
    let textBottom = baseline + capHeight + gap      // bottom of the last line

    // Arrow: shaft plus head, as wide as the text block above it.
    let arrowTop = textBottom - w * 0.05
    let arrowBottom = tile.minY + w * 0.08
    let arrowHeight = arrowTop - arrowBottom          // the head spans this full height
    let shaftHeight = arrowHeight * 0.44              // head flares well beyond the shaft
    let left = tile.midX - w * 0.37
    let right = tile.midX + w * 0.37
    let headLength = arrowHeight * 0.8
    let midY = (arrowTop + arrowBottom) / 2
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left, y: midY + shaftHeight / 2))
    path.addLine(to: CGPoint(x: right - headLength, y: midY + shaftHeight / 2))
    path.addLine(to: CGPoint(x: right - headLength, y: arrowTop))
    path.addLine(to: CGPoint(x: right, y: midY))
    path.addLine(to: CGPoint(x: right - headLength, y: arrowBottom))
    path.addLine(to: CGPoint(x: right - headLength, y: midY - shaftHeight / 2))
    path.addLine(to: CGPoint(x: left, y: midY - shaftHeight / 2))
    path.closeSubpath()
    ctx.setFillColor(signRed)
    ctx.addPath(path)
    ctx.fillPath()
}

func render(size: Int, macStyle: Bool, to url: URL) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }
    let s = CGFloat(size)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldSmoothFonts(true)
    // Apple's macOS icon grid: artwork is 824/1024 of the canvas with a ~185/1024 corner radius.
    let inset: CGFloat = macStyle ? s * 100 / 1024 : 0
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius: CGFloat = macStyle ? tile.width * 185 / 824 : 0

    if macStyle {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.02, color: CGColor(gray: 0, alpha: 0.35))
        ctx.setFillColor(signYellow)
        ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    drawSign(in: ctx, tile: tile)
    ctx.restoreGState()

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError() }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

render(size: 1024, macStyle: false, to: outDir.appendingPathComponent("ios-1024.png"))
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    render(size: pt * scale, macStyle: true, to: outDir.appendingPathComponent("mac-\(pt)x\(pt)@\(scale)x.png"))
}
print("rendered icons to \(outDir.path)")
