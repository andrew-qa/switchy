import AppKit
import SwitchyCore

/// Pre-rendered frames for one flag. All frames share one canvas size, so switching between
/// the still image and the animation never shifts the menu bar.
struct FlagArt {
    let still: NSImage
    let loop: [NSImage]
    let burst: [NSImage]
}

enum FlagAnimationTiming {
    static let framesPerSecond: Double = 15
    static let loopFrames = 30 // 2 s per wave
    static let burstFrames = 30 // 2 s, 1.5 waves
    static let burstCycles = 1.5
}

@MainActor
final class FlagArtCache {
    private var cache: [String: FlagArt] = [:]

    func art(for emoji: String) -> FlagArt? {
        if let art = cache[emoji] { return art }
        guard let art = FlagRenderer.makeArt(emoji) else { return nil }
        cache[emoji] = art
        return art
    }
}

/// Draws a flag emoji waving: each pixel column is shifted along a travelling sine wave and
/// shaded by the wave's slope.
@MainActor
enum FlagRenderer {
    static let scale: CGFloat = 2
    /// Flag height in points; the menu bar is ~24 pt tall.
    static let flagHeight: CGFloat = 12

    static func makeArt(_ emoji: String) -> FlagArt? {
        guard let flag = croppedEmoji(emoji) else { return nil }
        let heightPx = (flagHeight * scale).rounded()
        let widthPx = (heightPx * CGFloat(flag.width) / CGFloat(flag.height)).rounded()
        let wave = FlagWave(amplitude: Double(1.1 * scale), wavelength: Double(widthPx) * 0.95, shade: 0.24)
        let pad = (CGFloat(wave.amplitude) + 1).rounded(.up)
        let canvas = CGSize(width: widthPx, height: heightPx + 2 * pad)
        let flagRect = CGRect(x: 0, y: pad, width: widthPx, height: heightPx)

        func render(_ frame: WaveFrame) -> NSImage? {
            renderFrame(flag, canvas: canvas, flagRect: flagRect, wave: wave, frame: frame)
        }
        guard let still = render(.flat) else { return nil }
        let loop = FlagWave.loop(frameCount: FlagAnimationTiming.loopFrames).compactMap(render)
        let burst = FlagWave.burst(frameCount: FlagAnimationTiming.burstFrames, cycles: FlagAnimationTiming.burstCycles).compactMap(render)
        return FlagArt(still: still, loop: loop, burst: burst)
    }

    /// Renders the emoji large and cuts away the glyph's transparent padding.
    static func croppedEmoji(_ emoji: String) -> CGImage? {
        let size = 160
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let font = NSFont(name: "AppleColorEmoji", size: 120) ?? .systemFont(ofSize: 120)
        let text = NSAttributedString(string: emoji, attributes: [.font: font])
        let textSize = text.size()
        text.draw(at: NSPoint(x: (CGFloat(size) - textSize.width) / 2, y: (CGFloat(size) - textSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = ctx.data, let image = ctx.makeImage() else { return nil }
        let buffer = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: ctx.bytesPerRow * size)
        guard let bounds = AlphaBounds.find(in: buffer, width: size, height: size, bytesPerRow: ctx.bytesPerRow) else { return nil }
        // Bitmap rows run top to bottom, which is the coordinate space `cropping(to:)` expects.
        return image.cropping(to: CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height))
    }

    private static func renderFrame(_ flag: CGImage, canvas: CGSize, flagRect: CGRect, wave: FlagWave, frame: WaveFrame) -> NSImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high

        let width = Double(flagRect.width)
        for column in 0..<Int(flagRect.width) {
            let x = Double(column) + 0.5
            let strip = CGRect(x: CGFloat(column), y: 0, width: 1, height: canvas.height)
            ctx.saveGState()
            ctx.clip(to: strip)
            ctx.draw(flag, in: flagRect.offsetBy(dx: 0, dy: CGFloat(wave.offset(column: x, width: width, frame: frame))))
            let shade = wave.shading(column: x, width: width, frame: frame)
            if abs(shade) > 0.005 {
                // sourceAtop paints only over the flag pixels just drawn, never the transparent margin.
                ctx.setBlendMode(.sourceAtop)
                ctx.setFillColor(shade > 0 ? CGColor(gray: 1, alpha: shade) : CGColor(gray: 0, alpha: -shade))
                ctx.fill(strip)
            }
            ctx.restoreGState()
        }

        guard let image = ctx.makeImage() else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: canvas.width / scale, height: canvas.height / scale))
    }
}
