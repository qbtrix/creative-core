// JPEGWrite.swift: JPEG.write, a baseline JFIF 1.02 encoder (ITU-T T.81
// Annex A, F.1, K): sRGB bytes from PixelBuffer.rgba8, JFIF YCbCr, 4:2:0 by
// box average with edge replication, the K.1 / K.2 quantization tables scaled
// by quality, a float forward DCT over the decoder's cosine table, the K.3 to
// K.6 Huffman tables, one interleaved scan with 0xFF bytes stuffed.
// Invariants: quality and sides are checked before any pixel is read.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension JPEG {
    /// `buffer` as a baseline JFIF: un-premultiplied, then alpha dropped (a
    /// fully transparent pixel writes black), sRGB encoded, 4:2:0 chroma, one
    /// scan, the Annex K tables scaled by `quality` (1...100, higher keeps more
    /// detail). Throws `unsupported` for a quality outside 1...100, `tooLarge`
    /// for a side over `maxSide`.
    public static func write(_ buffer: PixelBuffer, quality: Int = 90) throws -> Data {
        guard (1...100).contains(quality) else { throw CodecError.unsupported("JPEG quality \(quality) is not in 1...100") }
        let width = buffer.width, height = buffer.height
        guard width <= maxSide, height <= maxSide else { throw CodecError.tooLarge("\(width)x\(height) pixels") }
        var e = JPEGEncoder(quality: quality)
        // Sides are at most maxSide (under SOF's 65,535), so no size product below can overflow.
        let rgba = try buffer.rgba8()
        let mcusX = (width + 15) / 16, mcusY = (height + 15) / 16
        var y = [[Float]](repeating: [Float](repeating: 0, count: 64), count: 4)
        var cb = [Float](repeating: 0, count: 64), cr = cb
        for my in 0..<mcusY {
            for mx in 0..<mcusX {
                for k in 0..<64 { (cb[k], cr[k]) = (0, 0) }
                for j in 0..<16 {
                    let row = min(my * 16 + j, height - 1) * width
                    for i in 0..<16 {
                        let o = (row + min(mx * 16 + i, width - 1)) * 4
                        let r = Float(rgba[o]), g = Float(rgba[o + 1]), b = Float(rgba[o + 2])
                        let luma: Float = 0.299 * r + 0.587 * g + 0.114 * b
                        y[j / 8 * 2 + i / 8][j % 8 * 8 + i % 8] = luma - 128
                        let c = j / 2 * 8 + i / 2
                        cb[c] += (0.5 * b - 0.168_736 * r - 0.331_264 * g) / 4
                        cr[c] += (0.5 * r - 0.418_688 * g - 0.081_312 * b) / 4
                    }
                }
                for k in 0..<4 { e.block(y[k], 0) }
                e.block(cb, 1)
                e.block(cr, 2)
            }
        }
        e.bits.flush()
        return Data(e.header(width, height) + e.bits.bytes + [0xFF, 0xD9])
    }
}

/// Entropy-coded bytes (F.1.2.3): most significant bit first, 0x00 stuffed after each 0xFF, padded with 1-bits.
struct JPEGBitWriter {
    var bytes: [UInt8] = [], acc = 0, count = 0

    mutating func put(_ value: Int, _ length: Int) {
        acc = acc << length | (value & ((1 << length) - 1))
        count += length
        while count >= 8 {
            count -= 8
            let b = UInt8(truncatingIfNeeded: acc >> count)
            bytes.append(b)
            if b == 0xFF { bytes.append(0) }
        }
        acc &= (1 << count) - 1
    }

    mutating func flush() { if count > 0 { put(0x7F, 8 - count) } }
}

/// A DHT table as written (B.2.4.2) with each symbol's code and length (C.1, C.2).
struct JPEGHuffmanCodes: Sendable {
    let bits: [UInt8], values: [UInt8]
    var code = [Int](repeating: 0, count: 256), size = [Int](repeating: 0, count: 256)

    init(_ bits: [UInt8], _ values: [UInt8]) {
        (self.bits, self.values) = (bits, values)
        var next = 0, k = 0
        for length in 1...16 {
            for _ in 0..<Int(bits[length - 1]) where k < values.count {
                (code[Int(values[k])], size[Int(values[k])]) = (next, length)
                (next, k) = (next + 1, k + 1)
            }
            next <<= 1
        }
    }

    /// K.5 or K.6: `head`, the values of codes up to 15 bits, then the 16-bit codes for every other run/size
    /// (sizes 1...10) run by run.
    static func ac(_ bits: [UInt8], _ head: [UInt8]) -> JPEGHuffmanCodes {
        let all: [UInt8] = (0..<16).flatMap { (r: Int) -> [UInt8] in (1...10).map { UInt8(r << 4 | $0) } }
        return JPEGHuffmanCodes(bits, head + all.filter { !head.contains($0) })
    }

    static let dcLuma = JPEGHuffmanCodes([0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0], Array(0...11))
    static let dcChroma = JPEGHuffmanCodes([0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0], Array(0...11))
    static let acLuma = ac([0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7D], lumaHead)
    static let acChroma = ac([0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77], chromaHead)
    static let lumaHead: [UInt8] = [
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14,
        0x32, 0x81, 0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72, 0x82]
    static let chromaHead: [UInt8] = [
        0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32,
        0x81, 0x08, 0x14, 0x42, 0x91, 0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0, 0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16,
        0x24, 0x34, 0xE1, 0x25, 0xF1]
}

/// The tables in effect for one write and the per-component DC predictions (F.1.2.1).
struct JPEGEncoder {
    /// K.1 and K.2, natural (row-major) order.
    static let lumaQ: [Int] = [16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57,
                               69, 56, 14, 17, 22, 29, 51, 87, 80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64,
                               81, 104, 113, 92, 49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99]
    static let chromaQ: [Int] = [17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99,
                                 99, 99, 47, 66, 99, 99, 99, 99, 99, 99] + [Int](repeating: 99, count: 32)

    /// Table 0 for Y, table 1 for Cb and Cr: K.1 and K.2 times 5000 / q below 50, else 200 - 2q, percent, in 1...255.
    let quant: [[Int]]
    var bits = JPEGBitWriter(), pred = [0, 0, 0]

    init(quality: Int) {
        let scale = quality < 50 ? 5000 / quality : 200 - 2 * quality
        quant = [Self.lumaQ, Self.chromaQ].map { t in t.map { min(max(($0 * scale + 50) / 100, 1), 255) } }
    }

    /// F.1.2: one level-shifted 8x8 block of component `c` (0 Y, 1 Cb, 2 Cr) transformed (A.3.3 with the decoder's
    /// orthonormal cosines: a row pass, then a column pass), quantized and Huffman coded.
    mutating func block(_ s: [Float], _ c: Int) {
        let t = JPEGDecoder.cosines, q = quant[min(c, 1)], zz = JPEGDecoder.zigzag
        var row = [Float](repeating: 0, count: 64), coef = [Int](repeating: 0, count: 64)
        for y in 0..<8 {
            for u in 0..<8 {
                var sum: Float = 0
                for x in 0..<8 { sum += t[x * 8 + u] * s[y * 8 + x] }
                row[y * 8 + u] = sum
            }
        }
        for v in 0..<8 {
            for u in 0..<8 {
                var sum: Float = 0
                for y in 0..<8 { sum += t[y * 8 + v] * row[y * 8 + u] }
                // An 8-bit block's coefficients stay within ±1,024, so the clamp only keeps the sizes in the tables.
                coef[v * 8 + u] = min(max(Int((sum / Float(q[v * 8 + u])).rounded()), -1023), 1023)
            }
        }
        let dc = c == 0 ? JPEGHuffmanCodes.dcLuma : .dcChroma, ac = c == 0 ? JPEGHuffmanCodes.acLuma : .acChroma
        let diff = coef[0] - pred[c]
        pred[c] = coef[0]
        put(dc, 0, diff)
        var run = 0
        for k in 1..<64 {
            let v = coef[zz[k]]
            if v == 0 { run += 1; continue }
            while run > 15 { bits.put(ac.code[0xF0], ac.size[0xF0]); run -= 16 }
            put(ac, run, v)
            run = 0
        }
        if run > 0 { bits.put(ac.code[0], ac.size[0]) }
    }

    /// F.1.2.1 and F.1.2.2: the code for run/size, then the size low bits of `v` (v - 1 when negative).
    mutating func put(_ table: JPEGHuffmanCodes, _ run: Int, _ v: Int) {
        let size = v == 0 ? 0 : Int.bitWidth - abs(v).leadingZeroBitCount, symbol = run << 4 | size
        bits.put(table.code[symbol], table.size[symbol])
        if size > 0 { bits.put(v < 0 ? v - 1 : v, size) }
    }

    static func segment(_ marker: UInt8, _ body: [UInt8]) -> [UInt8] {
        [0xFF, marker, UInt8(truncatingIfNeeded: (body.count + 2) >> 8), UInt8(truncatingIfNeeded: body.count + 2)] + body
    }

    /// SOI, APP0 JFIF 1.02 (no units, 1:1, no thumbnail), DQT, SOF0 (Y 2x2, Cb and Cr 1x1), DHT, SOS.
    func header(_ width: Int, _ height: Int) -> [UInt8] {
        func be16(_ v: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)] }
        let zz = JPEGDecoder.zigzag
        let dqt: [UInt8] = (0..<2).flatMap { (i: Int) -> [UInt8] in [UInt8(i)] + zz.map { UInt8(quant[i][$0]) } }
        let tables: [(UInt8, JPEGHuffmanCodes)] = [(0x00, .dcLuma), (0x10, .acLuma), (0x01, .dcChroma), (0x11, .acChroma)]
        var out: [UInt8] = [0xFF, 0xD8] + Self.segment(0xE0, Array("JFIF".utf8) + [0, 1, 2, 0, 0, 1, 0, 1, 0, 0])
        out += Self.segment(0xDB, dqt)
        out += Self.segment(0xC0, [8] + be16(height) + be16(width) + [3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1])
        out += Self.segment(0xC4, tables.flatMap { [$0.0] + $0.1.bits + $0.1.values })
        return out + Self.segment(0xDA, [3, 1, 0x00, 2, 0x11, 3, 0x11, 0, 63, 0])
    }
}
