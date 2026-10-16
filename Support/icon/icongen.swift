import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Usage: swiftc -O icongen.swift -o icongen && ./icongen wake-ev-map-2026-extracted.png ../../App/Assets.xcassets/AppIcon.appiconset
// Renders the app icon PNGs from the county's early-voting site map (extracted with a transparent
// background and contrast boosted by hand from the county's published JPEG).
let src = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
      let map = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("cannot load \(src.path)") }

/// Tile background: the navy of the county's title bar.
let navy = CGColor(srgbRed: 74/255, green: 85/255, blue: 120/255, alpha: 1)

/// Bounding box of the opaque pixels, so the map is centered regardless of how it was cropped.
func opaqueBounds(_ image: CGImage) -> CGRect {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 16 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    // CG bitmap rows run top-down; convert to the image's top-left coordinate space for cropping.
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let bounds = opaqueBounds(map)
let side = max(bounds.width, bounds.height)
let square = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)

func render(size: Int, macStyle: Bool, to url: URL) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }
    let s = CGFloat(size)
    ctx.interpolationQuality = .high
    // Apple's macOS icon grid: artwork is 824/1024 of the canvas with a ~185/1024 corner radius.
    let inset: CGFloat = macStyle ? s * 100 / 1024 : 0
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius: CGFloat = macStyle ? tile.width * 185 / 824 : 0

    if macStyle {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.02, color: CGColor(gray: 0, alpha: 0.35))
        ctx.setFillColor(navy)
        ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.setFillColor(navy)
    ctx.fill(tile)
    // Small breathing room; iOS applies its own squircle mask on top of the full-bleed square.
    let shrink: CGFloat = macStyle ? 0.05 : 0.08
    let artwork = tile.insetBy(dx: tile.width * shrink, dy: tile.height * shrink)
    // Map the square region of the source onto the artwork rect (CG y axis points up, so flip).
    let scale = artwork.width / square.width
    ctx.translateBy(x: artwork.minX - square.minX * scale,
                    y: artwork.minY + (square.maxY - CGFloat(map.height)) * scale)
    ctx.scaleBy(x: scale, y: scale)
    ctx.draw(map, in: CGRect(x: 0, y: 0, width: map.width, height: map.height))
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
print("source \(map.width)x\(map.height), opaque bounds \(Int(bounds.minX)),\(Int(bounds.minY)) \(Int(bounds.width))x\(Int(bounds.height)); rendered icons to \(outDir.path)")
