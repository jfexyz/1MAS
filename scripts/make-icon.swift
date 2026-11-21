// Writes the app icon as an Icon Composer document, Support/UnoMasApp/AppIcon.icon.
//
//   curl -o /tmp/1more-logo.png 'https://usa.1more.com/cdn/shop/files/logo_pc.png'
//   swift scripts/make-icon.swift /tmp/1more-logo.png
//
// The icon is the menu bar glyph (the SF Symbol `headphones`) in white on 1MORE's orange, with the
// "1" of 1MORE's wordmark in the space under the headband. macOS draws the shape, the glass, and
// the dark and tinted variants; the document holds only the background gradient and one glyph
// layer. It can be opened and adjusted in Icon Composer (in Xcode), and build-app.sh compiles it
// with actool. The "1" is cut from 1MORE's logo image, which is not in this repository.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: swift scripts/make-icon.swift <1MORE logo PNG> [output.icon]")
    exit(2)
}
let logoPath = arguments[1]
let output = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "Support/UnoMasApp/AppIcon.icon")

/// A colour as icon.json writes it.
func srgb(_ hex: UInt32) -> String {
    let parts = [hex >> 16 & 0xFF, hex >> 8 & 0xFF, hex & 0xFF].map { String(format: "%.5f", Double($0) / 255) }
    return "srgb:" + (parts + ["1.00000"]).joined(separator: ",")
}

// 1MORE's orange is the button colour on usa.1more.com, rgb(255, 61, 31); the gradient starts
// lighter at the top and ends on it.
let gradientTop = srgb(0xFF7A55)
let gradientBottom = srgb(0xFF3D1F)

/// The wordmark's "1" as an opaque mask, and its vertical stroke's centre as a fraction of its
/// width. In the logo image (2652 x 727 px) the "1" is the black shape around x 874-1005,
/// y 200-534.
func wordmarkOne() -> (mask: NSImage, stemCentre: CGFloat) {
    guard let data = FileManager.default.contents(atPath: logoPath), let rep = NSBitmapImageRep(data: data) else {
        print("cannot read \(logoPath)")
        exit(1)
    }
    var hits: [(x: Int, y: Int)] = []
    for y in 180..<550 {
        for x in 860..<1020 {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            if c.alphaComponent > 0.5, c.redComponent < 0.3, c.greenComponent < 0.3, c.blueComponent < 0.3 {
                hits.append((x, y))
            }
        }
    }
    guard !hits.isEmpty else {
        print("no \"1\" found where expected in \(logoPath); has the logo changed?")
        exit(1)
    }
    let minX = hits.map(\.x).min()!, maxX = hits.map(\.x).max()!
    let minY = hits.map(\.y).min()!, maxY = hits.map(\.y).max()!
    let w = maxX - minX + 1, h = maxY - minY + 1
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ink = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
    for hit in hits { out.setColor(ink, atX: hit.x - minX, y: hit.y - minY) }
    // Only the stem reaches the bottom fifth.
    let bottom = hits.filter { $0.y > maxY - h / 5 }.map(\.x)
    let stemCentre = (CGFloat(bottom.min()! + bottom.max()!) / 2 - CGFloat(minX)) / CGFloat(w)
    let mask = NSImage(size: NSSize(width: w, height: h))
    mask.addRepresentation(out)
    return (mask, stemCentre)
}

/// The glyph on a `size`-point canvas, laid out like the menu bar icon on its 18 pt canvas (symbol
/// at 14 pt, medium weight), with the "1" 6.4 units tall, its stem on the centre line, and its
/// middle 48% of the way down the symbol.
func glyph(size: CGFloat, one: (mask: NSImage, stemCentre: CGFloat)) -> NSImage {
    let s = size / 18
    let config = NSImage.SymbolConfiguration(pointSize: 14 * s, weight: .medium)
    let symbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    return NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
        let fit = min(size / symbol.size.width, size / symbol.size.height, 1)
        let w = symbol.size.width * fit, h = symbol.size.height * fit
        let frame = NSRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h)
        symbol.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let oneHeight = 6.4 * s
        let oneWidth = oneHeight * one.mask.size.width / one.mask.size.height
        one.mask.draw(in: NSRect(x: size / 2 - oneWidth * one.stemCentre, y: frame.minY + h * 0.48 - oneHeight / 2,
                                 width: oneWidth, height: oneHeight),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill(using: .sourceAtop)
        return true
    }
}

/// The glyph layer: 1024 px square, transparent, the glyph in white. Icon Composer's canvas is the
/// whole icon shape, and the glyph spans 78% of it, as it spanned the squircle in the first,
/// hand-drawn version of the icon.
func glyphLayer() -> Data {
    let pixels = 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let g: CGFloat = 796
    glyph(size: g, one: wordmarkOne())
        .draw(in: NSRect(x: (CGFloat(pixels) - g) / 2, y: (CGFloat(pixels) - g) / 2, width: g, height: g))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconJSON = """
{
  "fill" : {
    "linear-gradient" : [
      "\(gradientTop)",
      "\(gradientBottom)"
    ],
    "orientation" : {
      "start" : { "x" : 0.5, "y" : 0 },
      "stop" : { "x" : 0.5, "y" : 0.7 }
    }
  },
  "groups" : [
    {
      "layers" : [
        { "image-name" : "glyph.png", "name" : "glyph" }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : false, "value" : 0.5 }
    }
  ],
  "supported-platforms" : {
    "squares" : "shared"
  }
}

"""

let assets = output.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try glyphLayer().write(to: assets.appendingPathComponent("glyph.png"))
try iconJSON.write(to: output.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("Wrote \(output.path)")
