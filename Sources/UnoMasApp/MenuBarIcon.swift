import AppKit
import UnoMasKit

/// The menu bar icon: Apple's `headphones` SF Symbol, with a small letter in the open space under
/// the headband for the listen mode: "A" for active noise cancellation, "T" for transparency, "O" for
/// off, matching the first letters of the menu items. Dimmed, with no letter, while no headphones
/// are connected (or before the mode is first read).
enum MenuBarIcon {
    static func letter(for mode: ListenMode?) -> String? {
        switch mode {
        case .strongANC, .mildANC, .adaptiveANC, .windReduction: "A"
        case .transparent, .passThrough, .voiceEnhancement: "T"
        case .off: "O"
        case nil: nil
        }
    }

    static func image(mode: ListenMode?, connected: Bool) -> NSImage {
        let size: CGFloat = 18
        let alpha: CGFloat = connected ? 1 : 0.35
        let letter = connected ? letter(for: mode) : nil
        let symbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))!

        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let fit = min(size / symbol.size.width, size / symbol.size.height, 1)
            let width = symbol.size.width * fit
            let height = symbol.size.height * fit
            let frame = NSRect(x: (size - width) / 2, y: (size - height) / 2, width: width, height: height)
            symbol.draw(in: frame, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)

            if let letter {
                let text = NSAttributedString(string: letter, attributes: [
                    .font: NSFont.systemFont(ofSize: 7, weight: .bold),
                    .foregroundColor: NSColor.black.withAlphaComponent(alpha),
                ])
                let bounds = text.size()
                // Centred in the space under the headband, clear of the ear cups. The A's point
                // leaves its weight low, so it goes up half a point (one pixel on Retina) to look
                // level with the T and O. The image is flipped: up is negative.
                let lift: CGFloat = letter == "A" ? 0.5 : 0
                text.draw(at: NSPoint(x: (size - bounds.width) / 2, y: frame.minY + height * 0.42 - bounds.height / 2 - lift))
            }
            return true
        }
        // Template: macOS colours it for the menu bar's appearance, using only its alpha.
        image.isTemplate = true
        image.accessibilityDescription = mode.map { "Headphones: \($0.label)" } ?? "Headphones"
        return image
    }
}
