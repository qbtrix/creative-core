// PSD.swift: the PSD codec's entry points and limits, from the published PSD
// file format specification. `read` lives in PSDRead.swift and `write`'s
// validation and encoding in PSDWrite.swift.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Reads and writes 8- and 16-bit RGB and grayscale PSD files, with the
/// embedded ICC profile, as a `LayeredImage`.
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

    /// Saves an image as PSD bytes that `read` reopens equal: at
    /// `image.bitsPerChannel` (8 or 16), embedding `image.profile` as image
    /// resource 1039, and grayscale when that profile is gray (RGB otherwise).
    /// Throws a `CodecError`, before writing anything, for an image the format
    /// cannot hold: `unsupported` for another depth, a profile the ICC writer
    /// refuses, or a non-grey pixel under a gray profile; see PSDWrite.swift
    /// for the size limits.
    public static func write(_ image: LayeredImage) throws -> Data {
        try encode(image)
    }
}
