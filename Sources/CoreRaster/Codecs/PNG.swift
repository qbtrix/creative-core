// PNG.swift: the Foundation-only PNG codec (W3C PNG specification, third
// edition) and `PNGCodec`, the `PixelCodec` over it. Stubs until IC-4 (read)
// and IC-5 (write), which keep these signatures. Invariants: sizes come from
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
    /// Width and height in pixels (each 1...`PNG.maxSide`), and bits per
    /// sample (1, 2, 4, 8 or 16, as IHDR allows for the colour type).
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
    /// not 13 bytes, fails its CRC or pairs a bad depth and colour type;
    /// `tooLarge` for a side over `maxSide`. Until IC-4 it throws `unsupported`.
    public static func info(_ data: Data) throws -> PNGInfo {
        throw CodecError.unsupported("PNG.info waits on IC-4")
    }

    /// `data` decoded (every colour type, depths 1 to 16, Adam7) as
    /// premultiplied linear Float32 pixels: the sRGB transfer undone through
    /// `DisplayBytes`' rules, gAMA, cHRM and iCCP ignored, alpha from tRNS or 1.
    /// Throws what `info` throws, `damaged` for a bad chunk CRC, a type-3 image
    /// without PLTE, bad IDAT data or a bad filter type, and `tooLarge` past
    /// `maxSide` or `PixelBuffer.maxPixels` before allocating. Until IC-4 it
    /// throws `unsupported`.
    public static func read(_ data: Data) throws -> PixelBuffer {
        throw CodecError.unsupported("PNG.read waits on IC-4")
    }

    /// `buffer` as an sRGB RGBA PNG with `bitsPerChannel` (8 or 16) bits per
    /// sample, one IDAT per 64 KiB, each row given the filter with the least
    /// sum of absolute signed bytes (the spec's 12.8), compressed by
    /// `Deflate.zlib` at `level` (0...9). Throws `unsupported` for another
    /// depth, `tooLarge` for a side over `maxSide`. Until IC-5 it throws
    /// `unsupported`.
    public static func write(_ buffer: PixelBuffer, bitsPerChannel: Int = 8, level: Int = 6) throws -> Data {
        throw CodecError.unsupported("PNG.write waits on IC-5")
    }
}

/// The `PixelCodec` over `PNG`, so layered formats (ORA layers) read and
/// write real PNGs on every platform.
public struct PNGCodec: PixelCodec {
    /// The `Deflate` level used when writing, 0...9.
    let level: Int

    /// A codec that writes at `level` (0 stores, 9 compresses hardest).
    public init(level: Int = 6) { self.level = level }

    /// `data` through `PNG.read`. Throws `CodecError.pixelCodec` naming what
    /// `PNG.read` refused, as `PixelCodec` asks. Until IC-4 it throws
    /// `unsupported`.
    public func decodePNG(_ data: Data) throws -> PixelBuffer {
        throw CodecError.unsupported("PNGCodec.decodePNG waits on IC-4")
    }

    /// `buffer` through `PNG.write` at `bitsPerChannel` (8 or 16) and this
    /// codec's level. Throws `CodecError.pixelCodec` for another depth or
    /// anything `PNG.write` refuses, as `PixelCodec` asks. Until IC-5 it
    /// throws `unsupported`.
    public func encodePNG(_ buffer: PixelBuffer, bitsPerChannel: Int) throws -> Data {
        throw CodecError.unsupported("PNGCodec.encodePNG waits on IC-5")
    }
}
