// JPEG.swift: the Foundation-only JPEG codec (ITU-T T.81 with its Annex K
// tables, JFIF 1.02, the EXIF orientation tag). Stubs until IC-6 (baseline
// read), IC-7 (progressive read) and IC-8 (baseline write), which keep these
// signatures. Invariants: sizes come from SOF and are checked against
// `maxSide` and `PixelBuffer.maxPixels` before any pixel buffer is made;
// decoded pixels are never rotated, `JPEGInfo.orientation` says how to.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// What a JPEG's markers say, read without decoding any scan.
public struct JPEGInfo: Hashable, Sendable {
    /// Frame width and height in pixels (each 1...`JPEG.maxSide`) and the
    /// component count (1 grey, 3 YCbCr).
    public var width, height, components: Int
    /// True for a progressive frame (SOF2).
    public var progressive: Bool
    /// The EXIF orientation, 1...8; 1 when there is no EXIF tag.
    public var orientation: Int
}

/// JPEG files to and from `PixelBuffer`. Throws `CodecError`: `notThisFormat`
/// without SOI, `damaged` for a broken stream, `unsupported` for arithmetic
/// coding, lossless or hierarchical frames, 12-bit samples or CMYK,
/// `tooLarge` past its limits.
public enum JPEG {
    /// The largest width or height read or written, in pixels; the pixel
    /// count is also capped by `PixelBuffer.maxPixels`.
    public static let maxSide = 30_000

    /// The frame header and EXIF orientation of `data`, with no scan decoded.
    /// Throws `notThisFormat` without SOI, `damaged` for a malformed marker
    /// segment or no SOF, `unsupported` for a frame type it does not read,
    /// `tooLarge` for a side over `maxSide`. Until IC-6 it throws `unsupported`.
    public static func info(_ data: Data) throws -> JPEGInfo {
        throw CodecError.unsupported("JPEG.info waits on IC-6")
    }

    /// `data` decoded (baseline or progressive; grey or YCbCr at 4:4:4, 4:2:2
    /// or 4:2:0; restart markers) as premultiplied linear Float32 pixels with
    /// alpha 1, not rotated. Throws what `info` throws, `damaged` for a missing
    /// table, a bad Huffman code or a short scan, and `tooLarge` past `maxSide`
    /// or `PixelBuffer.maxPixels` before allocating. Until IC-6 (baseline) and
    /// IC-7 (progressive) it throws `unsupported`.
    public static func read(_ data: Data) throws -> PixelBuffer {
        throw CodecError.unsupported("JPEG.read waits on IC-6")
    }

    /// `buffer` as a baseline JFIF: alpha dropped, 4:2:0 chroma, one scan, the
    /// Annex K tables scaled by `quality` (1...100, higher keeps more detail).
    /// Throws `unsupported` for a quality outside 1...100, `tooLarge` for a
    /// side over `maxSide`. Until IC-8 it throws `unsupported`.
    public static func write(_ buffer: PixelBuffer, quality: Int = 90) throws -> Data {
        throw CodecError.unsupported("JPEG.write waits on IC-8")
    }
}
