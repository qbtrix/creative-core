// PSD.swift: the PSD codec's entry points and limits, from the published PSD
// file format specification. Read and write land in later tasks (PSDRead.swift,
// PSDWrite.swift); until then both throw `CodecError.unsupported("not built")`.
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

    /// Opens PSD bytes. Throws a `CodecError` for damaged or unsupported files.
    public static func read(_ data: Data) throws -> LayeredImage {
        throw CodecError.unsupported("not built")
    }

    /// Saves an image as PSD bytes.
    public static func write(_ image: LayeredImage) throws -> Data {
        throw CodecError.unsupported("not built")
    }
}
