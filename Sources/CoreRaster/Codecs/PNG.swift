// PNG.swift: the Foundation-only PNG codec (W3C PNG specification, third
// edition) and `PNGCodec`, the `PixelCodec` over it; the reader is in
// PNGRead.swift, the writer in PNGWrite.swift. Invariants: sizes come from
// IHDR and are checked against `maxSide` and `PixelBuffer.maxPixels` before
// any pixel buffer is made, and inflate is capped at the bytes IHDR implies;
// pixels are premultiplied linear Float32 both ways, files are sRGB.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// What a PNG's IHDR chunk says, read without decoding any pixels.
public struct PNGInfo: Hashable, Sendable {
    /// Width and height in pixels (each 1...`PNG.maxSide`, their product at
    /// most `PixelBuffer.maxPixels`, so `PNG.read` will not refuse the size),
    /// and bits per sample (1, 2, 4, 8 or 16, as IHDR allows for the colour type).
    public var width, height, bitDepth: Int
    /// The IHDR colour type: 0 grey, 2 RGB, 3 palette, 4 grey-alpha, 6 RGBA.
    public var colorType: Int
    /// True for Adam7 interlacing (IHDR interlace method 1).
    public var interlaced: Bool
}

/// PNG files to and from `PixelBuffer`. Throws `CodecError`: `notThisFormat`
/// without the PNG signature, `damaged` for a broken file, `unsupported` for
/// a feature it does not handle, `tooLarge` past its limits.
public enum PNG {
    /// The largest width or height read or written, in pixels (like PSD's);
    /// the pixel count is also capped by `PixelBuffer.maxPixels`.
    public static let maxSide = 30_000

    /// The IHDR fields of `data`, with no image data decoded. Throws
    /// `notThisFormat` without the signature; `damaged` when IHDR is not first,
    /// not 13 bytes, fails its CRC, has a zero width or height, pairs a bad
    /// depth and colour type, or names a compression or filter method other
    /// than 0 or an interlace method past 1; `tooLarge` for a side over
    /// `maxSide` or a pixel count over `PixelBuffer.maxPixels`, the same sizes
    /// `read` refuses.
    public static func info(_ data: Data) throws -> PNGInfo {
        try header(data).1
    }

    /// `data` decoded (every colour type, depths 1 to 16, Adam7) as
    /// premultiplied linear Float32 pixels: the sRGB transfer undone through
    /// `DisplayBytes`' rules, gAMA, cHRM and iCCP ignored; alpha from the alpha
    /// sample (colour types 4 and 6), from tRNS (types 0, 2 and 3), else 1.
    /// Throws what `info` throws; `damaged` for a bad chunk CRC, a second IHDR,
    /// a file that ends before IEND, no IDAT, a type-3 image without a valid
    /// PLTE, a tRNS longer than PLTE or of the wrong length for grey or RGB, a
    /// palette index past PLTE, IDAT data that does not inflate to exactly the
    /// bytes IHDR implies, or a bad filter type; `unsupported` for an unknown
    /// critical chunk.
    public static func read(_ data: Data) throws -> PixelBuffer {
        try decode(data)
    }

    /// The `CodecError.pixelCodec` text for `error` from `PNG.read` or
    /// `PNG.write`: the direction, what kind of failure, then the reason
    /// without its own "PNG" prefix, e.g. `PNG read: damaged file: IDAT chunk
    /// CRC mismatch` or `PNG write: unsupported: 12-bit samples: only 8 or 16`.
    static func pixelCodecText(_ error: any Error, writing: Bool) -> String {
        let way = writing ? "PNG write: " : "PNG read: "
        func reason(_ text: String) -> String {
            for prefix in ["PNG: ", "PNG "] where text.hasPrefix(prefix) { return String(text.dropFirst(prefix.count)) }
            return text
        }
        switch error as? CodecError {
        case .notThisFormat?: return way + "not a PNG"
        case .damaged(let text)?: return way + "damaged file: " + reason(text)
        case .unsupported(let text)?: return way + "unsupported: " + reason(text)
        case .tooLarge(let text)?: return way + "too large: " + reason(text)
        case .compressedEntry(let text)?, .pixelCodec(let text)?: return way + reason(text)
        case nil: return way + "\(error)"
        }
    }
}

/// The `PixelCodec` over `PNG`, so layered formats (ORA layers) read and
/// write real PNGs on every platform.
public struct PNGCodec: PixelCodec {
    /// The `Deflate` level used when writing, 0...9.
    let level: Int

    /// A codec that writes at `level` (0 stores, 9 compresses hardest); levels
    /// outside 0...9 act as the nearest end, as `Deflate.zlib` does.
    public init(level: Int = 6) { self.level = level }

    /// `data` through `PNG.read`. Throws `CodecError.pixelCodec` naming what
    /// `PNG.read` refused (`PNG.pixelCodecText`), as `PixelCodec` asks.
    public func decodePNG(_ data: Data) throws -> PixelBuffer {
        do { return try PNG.read(data) } catch { throw CodecError.pixelCodec(PNG.pixelCodecText(error, writing: false)) }
    }
}
