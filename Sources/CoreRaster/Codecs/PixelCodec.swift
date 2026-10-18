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
    func decodePNG(_ data: Data) throws -> PixelBuffer
    func encodePNG(_ buffer: PixelBuffer, bitsPerChannel: Int) throws -> Data
}

/// A test stand-in for PNG: not PNG at all, but a tiny header and the raw
/// components, so a round trip is exact. Layout, big-endian: the magic
/// `RAWP`, one byte of bits per channel (8 or 16, recorded only), UInt32
/// width, UInt32 height, then width x height x 4 Float32 bit patterns.
public struct RawPixelCodec: PixelCodec {
    static let magic: [UInt8] = Array("RAWP".utf8)
    static let headerCount = 13

    public init() {}

    public func encodePNG(_ buffer: PixelBuffer, bitsPerChannel: Int) throws -> Data {
        guard bitsPerChannel == 8 || bitsPerChannel == 16 else {
            throw CodecError.pixelCodec("bits per channel \(bitsPerChannel): only 8 or 16")
        }
        let components = buffer.components
        var bytes = Self.magic
        bytes.reserveCapacity(Self.headerCount + components.count * 4)
        bytes.append(UInt8(bitsPerChannel))
        // Width and height are at most maxPixels, so they fit in UInt32.
        for side in [buffer.width, buffer.height] { Self.appendBigEndian(UInt32(side), to: &bytes) }
        for value in components { Self.appendBigEndian(value.bitPattern, to: &bytes) }
        return Data(bytes)
    }

    public func decodePNG(_ data: Data) throws -> PixelBuffer {
        let bytes = [UInt8](data)
        guard bytes.count >= Self.headerCount, Array(bytes[0..<4]) == Self.magic else {
            throw CodecError.pixelCodec("not a raw pixel image")
        }
        guard bytes[4] == 8 || bytes[4] == 16 else {
            throw CodecError.pixelCodec("bits per channel \(bytes[4]): only 8 or 16")
        }
        let width = Int(Self.readBigEndian(bytes, at: 5))
        let height = Int(Self.readBigEndian(bytes, at: 9))
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
