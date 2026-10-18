// PSD.swift: the PSD codec's entry points and limits, from the published PSD
// file format specification. `read` lives in PSDRead.swift and `write`'s
// validation and encoding in PSDWrite.swift.
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
    /// The canvas counts once because the merged image decodes only its
    /// colour channels and one alpha; its other channels are skipped.
    public static let maxTotalPixels = PixelBuffer.maxPixels
    /// The deepest groups may nest, the same as `OpenRaster.maxDepth`.
    public static let maxDepth = OpenRaster.maxDepth

    /// Saves an image as 8-bit RGB PSD bytes that `read` reopens equal. Throws
    /// a `CodecError`, before writing anything, for an image the format cannot
    /// hold: see PSDWrite.swift.
    public static func write(_ image: LayeredImage) throws -> Data {
        try encode(image)
    }
}
