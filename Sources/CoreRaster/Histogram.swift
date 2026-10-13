// Histogram.swift: per-channel histograms of a PixelBuffer. Red, green, blue
// and Rec. 709 luminance are counted over unpremultiplied linear values
// (`RGBA.unpremultiplied`) clamped to 0...1, with clipping counts taken before
// the clamp. With `ToneEncoding.sRGB` each count is of the sRGB-encoded value
// instead (luminance: the encoded linear luminance), the axis levels and
// curves use in that encoding. Invariants a reader must keep: `bins` is in `binRange`, every
// channel array has `bins` entries, each channel's counts sum to the number of
// non-transparent pixels, and fully transparent pixels (alpha 0) are counted
// only in `transparent`. Bin k holds values in [k/bins, (k+1)/bins); the last
// bin also holds 1.

import CoreColor

/// Counts of a buffer's pixels by channel value, plus clipping counts.
public struct Histogram: Equatable, Hashable, Sendable {
    /// The bin counts a histogram accepts.
    public static let binRange = 2...4096

    /// Rec. 709 luminance weights for linear red, green and blue.
    public static let luminanceWeights = (r: Float(0.2126), g: Float(0.7152), b: Float(0.0722))

    /// The number of bins in each channel.
    public let bins: Int
    public let red: [Int]
    public let green: [Int]
    public let blue: [Int]
    /// Rec. 709 luminance of the clamped red, green and blue.
    public let luminance: [Int]
    /// Pixels with any color channel at or below 0.
    public let shadowClipped: Int
    /// Pixels with any color channel at or above 1.
    public let highlightClipped: Int
    /// Fully transparent pixels, which are in no channel's counts.
    public let transparent: Int

    /// Counts `buffer` into `bins` bins per channel, on linear or
    /// sRGB-encoded values. Throws `RasterError.invalid` when `bins` is
    /// outside `binRange`.
    public init(of buffer: PixelBuffer, bins: Int = 256, encoding: ToneEncoding = .linear) throws {
        guard Self.binRange.contains(bins) else {
            throw RasterError.invalid("histogram bins \(bins): must be in \(Self.binRange)")
        }
        var red = [Int](repeating: 0, count: bins), green = red, blue = red, luminance = red
        var shadowClipped = 0, highlightClipped = 0, transparent = 0
        let c = buffer.components, w = Self.luminanceWeights
        let shown: (Float) -> Float = encoding == .sRGB ? { Float(TransferCurve.encode(Double($0))) } : { $0 }
        for i in stride(from: 0, to: c.count, by: PixelBuffer.channels) {
            let p = RGBA(r: c[i], g: c[i + 1], b: c[i + 2], a: c[i + 3])
            guard p.a != 0 else {
                transparent += 1
                continue
            }
            let s = p.unpremultiplied()
            if s.r <= 0 || s.g <= 0 || s.b <= 0 { shadowClipped += 1 }
            if s.r >= 1 || s.g >= 1 || s.b >= 1 { highlightClipped += 1 }
            let r = min(max(s.r, 0), 1), g = min(max(s.g, 0), 1), b = min(max(s.b, 0), 1)
            red[Self.bin(shown(r), of: bins)] += 1
            green[Self.bin(shown(g), of: bins)] += 1
            blue[Self.bin(shown(b), of: bins)] += 1
            luminance[Self.bin(shown(w.r * r + w.g * g + w.b * b), of: bins)] += 1
        }
        self.bins = bins
        self.red = red
        self.green = green
        self.blue = blue
        self.luminance = luminance
        self.shadowClipped = shadowClipped
        self.highlightClipped = highlightClipped
        self.transparent = transparent
    }

    /// The bin of a value in 0...1; 1 (and any rounding past it) is the last bin.
    private static func bin(_ value: Float, of bins: Int) -> Int {
        min(max(Int(value * Float(bins)), 0), bins - 1)
    }
}
