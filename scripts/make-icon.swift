// Draws the app icon and writes Support/OneMoreMac/AppIcon.icns.
//
//   curl -o /tmp/1more-logo.png 'https://usa.1more.com/cdn/shop/files/logo_pc.png'
//   swift scripts/make-icon.swift /tmp/1more-logo.png
//
// The icon is the menu bar glyph (the SF Symbol `headphones`) in white on a macOS-style squircle
// in 1MORE's orange, with the "1" of 1MORE's wordmark in the space under the headband. The "1" is
// cut from 1MORE's logo image, which is not in this repository; the generated .icns is.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: swift scripts/make-icon.swift <1MORE logo PNG> [output.icns]")
    exit(2)
}
let logoPath = arguments[1]
let output = arguments.count > 2 ? arguments[2] : "Support/OneMoreMac/AppIcon.icns"

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// 1MORE's orange is the button colour on usa.1more.com, rgb(255, 61, 31); the gradient starts
// lighter at the top and ends on it.
let gradientTop = rgb(0xFF7A55)
let gradientBottom = rgb(0xFF3D1F)

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

/// A squircle (superellipse, exponent 5), close to the continuous-corner shape of macOS icons.
func squircle(_ r: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    let n = 5.0, steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let point = NSPoint(x: r.midX + r.width / 2 * CGFloat(copysign(pow(abs(c), 2 / n), c)),
                            y: r.midY + r.height / 2 * CGFloat(copysign(pow(abs(s), 2 / n), s)))
        i == 0 ? path.move(to: point) : path.line(to: point)
    }
    path.close()
    return path
}

/// The icon at `pixels` square, on Apple's macOS grid: an 824/1024 squircle with a soft drop
/// shadow and a vertical gradient, and the glyph with a faint shadow of its own.
func icon(pixels: Int, one: (mask: NSImage, stemCentre: CGFloat)) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = CGFloat(pixels) / 1024
    let path = squircle(NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u))

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -12 * u)
    shadow.shadowBlurRadius = 24 * u
    shadow.set()
    gradientBottom.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: gradientTop, ending: gradientBottom)!.draw(in: path, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    glyphShadow.shadowOffset = NSSize(width: 0, height: -6 * u)
    glyphShadow.shadowBlurRadius = 12 * u
    glyphShadow.set()
    let g = 640 * u
    glyph(size: g, one: one).draw(in: NSRect(x: (CGFloat(pixels) - g) / 2, y: (CGFloat(pixels) - g) / 2, width: g, height: g))
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let one = wordmarkOne()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = icon(pixels: points * scale, one: one).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", output, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("Wrote \(output)")
