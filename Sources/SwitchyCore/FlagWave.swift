import Foundation

/// One animation frame: where the wave is (phase, radians) and how strong it is (0 = flat, 1 = full).
public struct WaveFrame: Equatable, Sendable {
    public var phase: Double
    public var strength: Double

    public init(phase: Double, strength: Double) {
        self.phase = phase
        self.strength = strength
    }

    public static let flat = WaveFrame(phase: 0, strength: 0)
}

/// Geometry of a flag waving from a pole on its left edge. The renderer shifts each pixel column
/// of the flag by `offset` and lightens or darkens it by `shading` to suggest folds.
public struct FlagWave: Sendable {
    /// Largest vertical displacement at the free edge, in pixels.
    public var amplitude: Double
    /// Length of one wave across the flag, in pixels.
    public var wavelength: Double
    /// Largest brightness change: +shade is white at that alpha, -shade is black.
    public var shade: Double

    public init(amplitude: Double, wavelength: Double, shade: Double) {
        self.amplitude = amplitude
        self.wavelength = wavelength
        self.shade = shade
    }

    public func offset(column x: Double, width: Double, frame: WaveFrame) -> Double {
        amplitude * frame.strength * Self.freedom(x, width) * sin(angle(x, frame))
    }

    /// Folds facing up catch the light. Uses the wave's slope, so it leads the offset by a quarter turn.
    public func shading(column x: Double, width: Double, frame: WaveFrame) -> Double {
        shade * frame.strength * Self.freedom(x, width) * cos(angle(x, frame))
    }

    private func angle(_ x: Double, _ frame: WaveFrame) -> Double {
        // kx - ωt: the wave travels away from the pole.
        2 * .pi * x / wavelength - frame.phase
    }

    /// 0 at the pole (left edge), 1 at the free edge.
    static func freedom(_ x: Double, _ width: Double) -> Double {
        guard width > 0 else { return 0 }
        return min(max(x / width, 0), 1)
    }

    /// Endless waving: evenly spaced phases, so the last frame flows back into the first.
    public static func loop(frameCount: Int) -> [WaveFrame] {
        guard frameCount > 0 else { return [] }
        return (0..<frameCount).map { WaveFrame(phase: 2 * .pi * Double($0) / Double(frameCount), strength: 1) }
    }

    /// A short wave that starts and ends perfectly flat, so it can play on top of a still flag.
    public static func burst(frameCount: Int, cycles: Double) -> [WaveFrame] {
        guard frameCount > 1 else { return frameCount == 1 ? [.flat] : [] }
        let last = Double(frameCount - 1)
        return (0..<frameCount).map { k in
            let t = Double(k) / last
            return WaveFrame(phase: 2 * .pi * cycles * t, strength: k == 0 || k == frameCount - 1 ? 0 : sin(.pi * t))
        }
    }
}

public struct PixelRect: Equatable, Sendable {
    public var x, y, width, height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum AlphaBounds {
    /// Smallest rectangle (top-left origin) that holds every pixel more opaque than `threshold`,
    /// in an RGBA buffer. Used to cut a flag emoji out of its padded glyph box.
    public static func find(
        in rgba: UnsafeBufferPointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        threshold: UInt8 = 16
    ) -> PixelRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width where rgba[row + x * 4 + 3] > threshold {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        return PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
