// PNGFixtures.swift: PNG files assembled byte by byte from the W3C PNG
// specification (third edition) for the image-codecs checks (IC-2). Chunks
// are length, type, body and the CRC-32 of type and body (5.3); image data
// is a zlib stream (RFC 1950) of stored DEFLATE blocks (RFC 1951, 3.2.4,
// BTYPE 00), so no compressor is involved; rows are filtered with the
// spec's five filters (9.2) and laid out by depth (7.2) and Adam7 (8.2).
// Expected pixels come from the same samples by the spec's rules, never
// from a decoder.
@testable import CoreRaster
import CoreColor
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum PNGFixtures {
    static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    /// Adam7 passes (8.2): x start, y start, x step, y step.
    static let adam7 = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]

    static func be32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: v >> (24 - 8 * $0)) } }

    /// One chunk: big-endian length, type, body, CRC-32 over type and body.
    static func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        let typed = Array(type.utf8) + body
        return be32(body.count) + typed + be32(Int(ByteReader.crc32(typed)))
    }

    static func ihdr(_ width: Int, _ height: Int, depth: Int, colorType: Int, interlace: Int = 0) -> [UInt8] {
        be32(width) + be32(height) + [UInt8(depth), UInt8(colorType), 0, 0, UInt8(interlace)]
    }

    /// RFC 1950, 8.2: two sums modulo 65,521.
    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes { a = (a + UInt32(byte)) % 65_521; b = (b + a) % 65_521 }
        return b << 16 | a
    }

    /// `raw` wrapped as zlib: CMF 0x78, FLG 0x01 (check bits make 0x7801 a multiple of 31), the DEFLATE bytes, Adler-32 of `output`.
    static func zlib(_ raw: [UInt8], of output: [UInt8]) -> [UInt8] { [0x78, 0x01] + raw + be32(Int(adler32(output))) }

    /// `bytes` as stored blocks of at most `block` bytes (BFINAL on the last, LEN then its complement NLEN), zlib-wrapped.
    static func stored(_ bytes: [UInt8], block: Int = 65_535) -> [UInt8] {
        var raw: [UInt8] = [], start = 0
        repeat {
            let n = min(block, bytes.count - start)
            raw += [start + n == bytes.count ? 1 : 0, UInt8(n & 0xFF), UInt8(n >> 8), UInt8(~n & 0xFF), UInt8((~n >> 8) & 0xFF)]
            raw += bytes[start..<(start + n)]
            start += n
        } while start < bytes.count
        return zlib(raw, of: bytes)
    }

    /// Samples per pixel for a colour type (6.1).
    static func channels(_ colorType: Int) -> Int { [1, 0, 3, 1, 2, 0, 4][colorType] }

    /// Row bytes for `samples` (each `depth` bits, packed high bits first, the row padded to a byte; 16-bit big-endian; 7.2).
    static func packRow(_ samples: [Int], depth: Int) -> [UInt8] {
        if depth == 16 { return samples.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] } }
        var row = [UInt8](repeating: 0, count: (samples.count * depth + 7) / 8)
        for (i, s) in samples.enumerated() { row[i * depth / 8] |= UInt8(s << (8 - depth - i * depth % 8)) }
        return row
    }

    /// The Paeth predictor (9.4): ties go to a, then b.
    static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        return pa <= pb && pa <= pc ? a : (pb <= pc ? b : c)
    }

    /// `row` with `filter` (0 None, 1 Sub, 2 Up, 3 Average, 4 Paeth) against `prior`, `bpp` bytes per complete pixel (9.2).
    static func filtered(_ row: [UInt8], prior: [UInt8]?, filter: Int, bpp: Int) -> [UInt8] {
        [UInt8(filter)] + row.indices.map { i in
            let a = i >= bpp ? Int(row[i - bpp]) : 0, b = Int(prior?[i] ?? 0), c = i >= bpp ? Int(prior?[i - bpp] ?? 0) : 0
            let predictor = [0, a, b, (a + b) / 2, paeth(a, b, c)][filter]
            return UInt8(truncatingIfNeeded: Int(row[i]) - predictor)
        }
    }

    /// The filtered scanlines of a `pixels` grid (rows of per-pixel samples), one pass or Adam7; filter type `filter(row index)`.
    static func scanlines(_ pixels: [[[Int]]], depth: Int, bpp: Int, interlaced: Bool, filter: (Int) -> Int = { _ in 0 }) -> [UInt8] {
        let height = pixels.count, width = pixels.first?.count ?? 0
        let passes = interlaced ? adam7 : [(0, 0, 1, 1)]
        var out: [UInt8] = [], index = 0
        for (x0, y0, dx, dy) in passes where x0 < width && y0 < height {
            var prior: [UInt8]?
            for y in stride(from: y0, to: height, by: dy) {
                let row = packRow(stride(from: x0, to: width, by: dx).flatMap { pixels[y][$0] }, depth: depth)
                out += filtered(row, prior: prior, filter: filter(index), bpp: bpp)
                prior = row
                index += 1
            }
        }
        return out
    }

    /// A whole PNG of `pixels`; `extra` chunks go between IHDR and IDAT; the zlib stream is split over `idats` chunks.
    static func png(_ pixels: [[[Int]]], depth: Int, colorType: Int, interlaced: Bool = false, extra: [[UInt8]] = [],
                    idats: Int = 1, filter: (Int) -> Int = { _ in 0 }) -> Data {
        let bpp = max(1, channels(colorType) * depth / 8)
        let stream = stored(scanlines(pixels, depth: depth, bpp: bpp, interlaced: interlaced, filter: filter))
        let size = (stream.count + idats - 1) / idats
        let parts = stride(from: 0, to: stream.count, by: size).map { chunk("IDAT", Array(stream[$0..<min($0 + size, stream.count)])) }
        let head = chunk("IHDR", ihdr(pixels.first?.count ?? 0, pixels.count, depth: depth, colorType: colorType, interlace: interlaced ? 1 : 0))
        let bytes: [UInt8] = signature + head + Array(extra.joined()) + Array(parts.joined()) + chunk("IEND", [])
        return Data(bytes)
    }

    /// A `width` x `height` grid whose samples run through every value a depth holds, distinct per channel.
    static func ramp(_ width: Int, _ height: Int, channels: Int, depth: Int) -> [[[Int]]] {
        let levels = 1 << depth
        return (0..<height).map { y in (0..<width).map { x in (0..<channels).map { c in ((y * width + x) * 37 + c * 101 + 13) % levels } } }
    }

    /// What the spec says a pixel of samples `s` is (straight, encoded 0...1): grey and RGB scaled by 2^depth - 1,
    /// palette entries from `palette` with `alpha` from tRNS (255 past its end), and a tRNS `key` matching grey or RGB clear.
    static func straight(_ s: [Int], colorType: Int, depth: Int, palette: [[Int]] = [], alpha: [Int] = [], key: [Int]? = nil) -> [Double] {
        let top = Double((1 << depth) - 1)
        switch colorType {
        case 0: return [Double(s[0]) / top, Double(s[0]) / top, Double(s[0]) / top, s == key ? 0 : 1]
        case 2: return s.map { Double($0) / top } + [s == key ? 0 : 1]
        case 3: return palette[s[0]].map { Double($0) / 255 } + [Double(s[0] < alpha.count ? alpha[s[0]] : 255) / 255]
        case 4: return [s[0], s[0], s[0], s[1]].map { Double($0) / top }
        default: return s.map { Double($0) / top }
        }
    }

    /// Straight sRGB-encoded pixels as the premultiplied linear buffer a reader must return (IEC 61966-2-1 transfer).
    static func linear(_ rows: [[[Double]]]) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: rows.first?.count ?? 0, height: rows.count)
        for (y, row) in rows.enumerated() {
            for (x, p) in row.enumerated() {
                let c = p.prefix(3).map { Float(TransferCurve.decode($0)) }
                try buffer.setPixel(x: x, y: y, RGBA(r: c[0], g: c[1], b: c[2], a: Float(p[3])).premultiplied())
            }
        }
        return buffer
    }

    /// The largest difference between two buffers' components; infinity when their sizes differ.
    static func maxDifference(_ a: PixelBuffer, _ b: PixelBuffer) throws -> Float {
        guard a.width == b.width, a.height == b.height else { return .infinity }
        var worst: Float = 0
        for y in 0..<a.height {
            for x in 0..<a.width {
                let p = try a.pixel(x: x, y: y), q = try b.pixel(x: x, y: y)
                worst = max(worst, abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a))
            }
        }
        return worst
    }

    /// The `CodecError` case `body` throws, by name ("notThisFormat", "damaged", "unsupported", "tooLarge",
    /// "pixelCodec"), "returned" when it returns, or "other" for another error.
    static func thrown(_ body: () throws -> Any) -> String {
        do { _ = try body(); return "returned" } catch let error as CodecError {
            return String(String(describing: error).prefix { $0 != "(" })
        } catch { return "other" }
    }

    /// The chunks of a PNG after its signature: type, body and whether the stored CRC matches.
    static func chunks(_ data: Data) -> [(type: String, body: [UInt8], crcOK: Bool)] {
        let bytes = [UInt8](data)
        var out: [(String, [UInt8], Bool)] = [], at = 8
        while at + 12 <= bytes.count {
            let n = bytes[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) }
            guard at + 12 + n <= bytes.count else { break }
            let typed = Array(bytes[(at + 4)..<(at + 8 + n)])
            let crc = bytes[(at + 8 + n)..<(at + 12 + n)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            out.append((String(decoding: typed.prefix(4), as: UTF8.self), Array(typed.dropFirst(4)), crc == ByteReader.crc32(typed)))
            at += 12 + n
        }
        return out
    }
}
