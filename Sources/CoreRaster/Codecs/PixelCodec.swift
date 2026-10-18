// PixelCodec.swift: the injected PNG codec layered formats use for their
// per-layer images, so this module stays Foundation only. Apps conform their
// platform image codec; Linux tests use RawPixelCodec, a lossless stand-in.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Turns PNG bytes into a `PixelBuffer` and back. Implementations throw
/// `CodecError.pixelCodec` for bytes they cannot read.
public protocol PixelCodec: Sendable {
    /// PNG bytes as premultiplied linear Float32 pixels. Must read 8- and
    /// 16-bit PNGs.
    func decodePNG(_ data: Data) throws -> PixelBuffer
    /// `buffer` (premultiplied linear light) as a PNG. `bitsPerChannel` is 8
    /// or 16: write the PNG's samples at that depth and record it as the
    /// IHDR bit depth (byte 24), which `OpenRaster.read` uses to report the
    /// image's depth. Throw `CodecError.pixelCodec` for any other value.
    func encodePNG(_ buffer: PixelBuffer, bitsPerChannel: Int) throws -> Data
}

/// A test stand-in for PNG: a PNG's signature and IHDR chunk, laid out as
/// the PNG spec has them, so a reader can size it before decoding, then the
/// raw components instead of IDAT, so a round trip is exact. Layout,
/// big-endian: the 8-byte PNG signature, the IHDR chunk (length 13, `IHDR`,
/// UInt32 width, UInt32 height, bit depth 8 or 16 (recorded only), colour
/// type 6, three zero bytes, its CRC-32), then width x height x 4 Float32
/// bit patterns.
public struct RawPixelCodec: PixelCodec {
    static let magic: [UInt8] = OpenRaster.pngSignature + [0, 0, 0, 13] + Array("IHDR".utf8)
    static let headerCount = 33

    public init() {}

    public func encodePNG(_ buffer: PixelBuffer, bitsPerChannel: Int) throws -> Data {
        guard bitsPerChannel == 8 || bitsPerChannel == 16 else {
            throw CodecError.pixelCodec("bits per channel \(bitsPerChannel): only 8 or 16")
        }
        let components = buffer.components
        var bytes = Self.magic
        bytes.reserveCapacity(Self.headerCount + components.count * 4)
        // Width and height are at most maxPixels, so they fit in UInt32.
        for side in [buffer.width, buffer.height] { Self.appendBigEndian(UInt32(side), to: &bytes) }
        bytes += [UInt8(bitsPerChannel), 6, 0, 0, 0]
        Self.appendBigEndian(ZipStore.crc32(bytes[12...]), to: &bytes)
        for value in components { Self.appendBigEndian(value.bitPattern, to: &bytes) }
        return Data(bytes)
    }

    public func decodePNG(_ data: Data) throws -> PixelBuffer {
        let bytes = [UInt8](data)
        guard bytes.count >= Self.headerCount, bytes.starts(with: Self.magic) else {
            throw CodecError.pixelCodec("not a raw pixel image")
        }
        guard bytes[24] == 8 || bytes[24] == 16 else {
            throw CodecError.pixelCodec("bits per channel \(bytes[24]): only 8 or 16")
        }
        let width = Int(Self.readBigEndian(bytes, at: 16))
        let height = Int(Self.readBigEndian(bytes, at: 20))
        let pixels: Int
        do {
            pixels = try PixelBuffer.validatedSize(width: width, height: height)
        } catch {
            throw CodecError.pixelCodec("size \(width)x\(height) is not a valid buffer")
        }
        // pixels <= maxPixels, so the component and byte counts cannot overflow.
        let count = pixels * PixelBuffer.channels
        guard bytes.count == Self.headerCount + count * 4 else {
            throw CodecError.pixelCodec("\(bytes.count) bytes for \(width)x\(height)")
        }
        var storage = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let value = Float(bitPattern: Self.readBigEndian(bytes, at: Self.headerCount + i * 4))
            guard value.isFinite else { throw CodecError.pixelCodec("component \(i) is not finite") }
            storage[i] = value
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: storage)
    }

    private static func appendBigEndian(_ value: UInt32, to bytes: inout [UInt8]) {
        for shift in stride(from: 24, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) }
    }

    /// The caller has checked that `offset + 4 <= bytes.count`.
    private static func readBigEndian(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset..<(offset + 4)].reduce(0) { $0 << 8 | UInt32($1) }
    }
}
