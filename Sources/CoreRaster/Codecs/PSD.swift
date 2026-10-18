// PSD.swift: the PSD codec's entry points and limits, from the published PSD
// file format specification. `read` lives in PSDRead.swift; write lands in a
// later task (PSDWrite.swift) and until then throws
// `CodecError.unsupported("not built")`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Reads and writes 8-bit RGB and grayscale PSD files as a `LayeredImage`.
public enum PSD {
    /// The largest width or height a PSD (not the large document format) may have.
    public static let maxSide = 30_000
    /// The most layer records a file may declare.
    public static let maxLayers = 8_000
    /// The most pixels the canvas, every layer and every mask may hold together
    /// (summed from the record bounds before any channel is decoded): the
    /// same cap as one `PixelBuffer`, so a file cannot multiply it by layers.
    public static let maxTotalPixels = PixelBuffer.maxPixels

    /// Saves an image as PSD bytes.
    public static func write(_ image: LayeredImage) throws -> Data {
        throw CodecError.unsupported("not built")
    }
}
