// PNGWrite.swift: PNG.write and PNGCodec.encodePNG, from the W3C PNG
// specification (third edition) only. Pixels are unpremultiplied and sRGB
// encoded through the existing helpers (DisplayBytes at 8 bits; PSD's 16-bit
// linear table and sample rounding at 16), samples are big-endian (7.1), and
// each row takes the filter (9.2) with the least sum of its bytes read as
// signed (12.8), costed for all five filters in one pass. The stream is
// `Deflate.zlib`, split into IDATs of at most 64 KiB; every chunk carries the
// CRC-32 of its type and body (5.3). Sizes are checked before anything is
// allocated, with overflow-checked arithmetic.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension PNG {
    /// The most bytes one IDAT chunk holds.
    static let idatBytes = 65_536

    /// `buffer` as an sRGB RGBA PNG with `bitsPerChannel` (8 or 16) bits per
    /// sample, one IDAT per 64 KiB, each row given the filter with the least
    /// sum of absolute signed bytes (the spec's 12.8), compressed by
    /// `Deflate.zlib` at `level` (0...9). Throws `unsupported` for another
    /// depth, `tooLarge` for a side over `maxSide`.
    public static func write(_ buffer: PixelBuffer, bitsPerChannel: Int = 8, level: Int = 6) throws -> Data {
        guard bitsPerChannel == 8 || bitsPerChannel == 16 else {
            throw CodecError.unsupported("PNG \(bitsPerChannel)-bit samples: only 8 or 16")
        }
        guard buffer.width <= maxSide, buffer.height <= maxSide else {
            throw CodecError.tooLarge("PNG \(buffer.width)x\(buffer.height): sides are at most \(maxSide)")
        }
        let bpp = bitsPerChannel / 2
        let rowBytes = try ByteReader.multiplying(buffer.width, bpp)
        let samples = bitsPerChannel == 8 ? try buffer.rgba8() : samples16(buffer)
        let lines = try filtered(samples, rowBytes: rowBytes, height: buffer.height, bpp: bpp)
        let stream = [UInt8](Deflate.zlib(Data(lines), level: level))
        var header: [UInt8] = []
        appendBigEndian(UInt32(buffer.width), to: &header)
        appendBigEndian(UInt32(buffer.height), to: &header)
        header += [UInt8(bitsPerChannel), 6, 0, 0, 0]
        var out = OpenRaster.pngSignature
        out.reserveCapacity(stream.count + stream.count / idatBytes * 12 + 57)
        appendChunk("IHDR", header[...], to: &out)
        for start in stride(from: 0, to: stream.count, by: idatBytes) {
            appendChunk("IDAT", stream[start..<min(start + idatBytes, stream.count)], to: &out)
        }
        appendChunk("IEND", [], to: &out)
        return Data(out)
    }

    /// Unpremultiplied 16-bit sRGB samples, high byte first: colour as the
    /// encoded sample whose linear light is nearest, alpha rounded.
    static func samples16(_ buffer: PixelBuffer) -> [UInt8] {
        let components = buffer.components, table = PSD.linear16, spans = PSD.spans16
        var out = [UInt8](repeating: 0, count: components.count * 2)
        func put(_ v: Int, _ j: Int) {
            out[j] = UInt8(truncatingIfNeeded: v >> 8); out[j + 1] = UInt8(truncatingIfNeeded: v)
        }
        for i in stride(from: 0, to: components.count, by: 4) {
            let p = RGBA(r: components[i], g: components[i + 1], b: components[i + 2], a: components[i + 3])
                .unpremultiplied()
            put(PSD.nearest(p.r, in: table, spans: spans), i * 2)
            put(PSD.nearest(p.g, in: table, spans: spans), i * 2 + 2)
            put(PSD.nearest(p.b, in: table, spans: spans), i * 2 + 4)
            put(PSDDepth.sixteen.quantized(p.a), i * 2 + 6)
        }
        return out
    }

    /// `samples` (`height` rows of `rowBytes`) as filtered scanlines: each row
    /// a filter-type byte, then its bytes minus the predictor (9.2), the
    /// filter the one with the least sum of absolute signed bytes, ties to the
    /// lower type.
    static func filtered(_ samples: [UInt8], rowBytes: Int, height: Int, bpp: Int) throws -> [UInt8] {
        let count = try ByteReader.multiplying(ByteReader.adding(rowBytes, 1), height)
        guard samples.count == rowBytes * height else {
            throw CodecError.damaged("\(samples.count) sample bytes for \(height) rows of \(rowBytes)")
        }
        var out = [UInt8](repeating: 0, count: count)
        var costs = [Int](repeating: 0, count: 5)
        samples.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<height {
                    let row = y * rowBytes, up = row - rowBytes, line = y * (rowBytes + 1)
                    func neighbours(_ i: Int) -> (x: Int, a: Int, b: Int, c: Int) {
                        let left = i >= bpp, above = y > 0
                        return (Int(src[row + i]), left ? Int(src[row + i - bpp]) : 0, above ? Int(src[up + i]) : 0,
                                left && above ? Int(src[up + i - bpp]) : 0)
                    }
                    var none = 0, sub = 0, upCost = 0, average = 0, paethCost = 0
                    for i in 0..<rowBytes {
                        let n = neighbours(i)
                        none += weight(n.x)
                        sub += weight(n.x - n.a)
                        upCost += weight(n.x - n.b)
                        average += weight(n.x - (n.a + n.b) / 2)
                        paethCost += weight(n.x - paeth(n.a, n.b, n.c))
                    }
                    costs[0] = none; costs[1] = sub; costs[2] = upCost; costs[3] = average; costs[4] = paethCost
                    var best = 0
                    for filter in 1..<5 where costs[filter] < costs[best] { best = filter }
                    dst[line] = UInt8(best)
                    for i in 0..<rowBytes {
                        let n = neighbours(i)
                        dst[line + 1 + i] = UInt8(truncatingIfNeeded: n.x - predictor(best, n.a, n.b, n.c))
                    }
                }
            }
        }
        return out
    }

    /// A filtered byte's cost: its absolute value read as a signed byte.
    @inline(__always) static func weight(_ difference: Int) -> Int {
        let signed = Int(Int8(truncatingIfNeeded: difference))
        return signed < 0 ? -signed : signed
    }

    /// The predictor of `filter` (0 None, 1 Sub, 2 Up, 3 Average, 4 Paeth) from left, above and upper left.
    @inline(__always) static func predictor(_ filter: Int, _ a: Int, _ b: Int, _ c: Int) -> Int {
        switch filter {
        case 1: return a
        case 2: return b
        case 3: return (a + b) / 2
        case 4: return paeth(a, b, c)
        default: return 0
        }
    }

    static func appendBigEndian(_ value: UInt32, to bytes: inout [UInt8]) {
        for shift in stride(from: 24, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) }
    }

    /// One chunk (5.3): the body's length, the type, the body, then the CRC-32 of type and body.
    /// Bodies here are at most `idatBytes`, so the length fits in UInt32.
    static func appendChunk(_ type: String, _ body: ArraySlice<UInt8>, to out: inout [UInt8]) {
        appendBigEndian(UInt32(body.count), to: &out)
        let start = out.count
        out += Array(type.utf8)
        out += body
        appendBigEndian(ByteReader.crc32(out[start...]), to: &out)
    }
}

extension PNGCodec {
    /// `buffer` through `PNG.write` at `bitsPerChannel` (8 or 16) and this
    /// codec's level. Throws `CodecError.pixelCodec` for another depth or
    /// anything `PNG.write` refuses, as `PixelCodec` asks.
    public func encodePNG(_ buffer: PixelBuffer, bitsPerChannel: Int) throws -> Data {
        do {
            return try PNG.write(buffer, bitsPerChannel: bitsPerChannel, level: level)
        } catch {
            throw CodecError.pixelCodec("PNG write refused: \(error)")
        }
    }
}
