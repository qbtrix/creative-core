// JPEGDecode.swift: JPEG.read's entropy half (T.81 Annex C, F.2): Huffman
// tables, a bit reader over one de-stuffed restart interval, the sequential
// scan, and the coefficients-to-pixels stage IC-7's progressive scans share.
import CoreColor
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A DHT table (C.2, F.2.2.3): `fast` (length << 8 | value) for codes up to 9 bits, maxCode and offset past that.
struct JPEGHuffman: Sendable {
    var fast = [UInt16](repeating: 0, count: 512), maxCode = [Int](repeating: -1, count: 17)
    var offset = [Int](repeating: 0, count: 17), values: [UInt8]

    init(counts: [UInt8], values: [UInt8]) throws {
        self.values = values
        var code = 0, k = 0
        for length in 1...16 {
            let n = Int(counts[length - 1])
            guard code + n <= 1 << length else { throw CodecError.damaged("DHT has too many \(length)-bit codes") }
            offset[length] = k - code
            for _ in 0..<n {
                let shift = 9 - length
                if shift >= 0 {
                    for j in 0..<(1 << shift) { fast[code << shift | j] = UInt16(length << 8) | UInt16(values[k]) }
                }
                (code, k) = (code + 1, k + 1)
            }
            if n > 0 { maxCode[length] = code - 1 }
            code <<= 1
        }
    }
}

/// Bits MSB first over one restart interval; past the end it reads padding 1-bits and `overrun` turns true.
struct JPEGBits {
    let bytes: [UInt8]
    var next = 0, acc: UInt64 = 0, count = 0

    var overrun: Bool { next * 8 - count > bytes.count * 8 }

    mutating func peek(_ n: Int) -> Int {
        while count <= 56 {
            let b: UInt64 = next < bytes.count ? UInt64(bytes[next]) : 0xFF
            acc |= b << UInt64(56 - count)
            next += 1
            count += 8
        }
        return Int(truncatingIfNeeded: acc >> UInt64(64 - n))
    }

    mutating func skip(_ n: Int) { acc <<= UInt64(n); count -= n }

    /// F.2.2.1 RECEIVE then EXTEND: `s` bits as a signed value (0 for s = 0).
    mutating func receive(_ s: Int) -> Int32 {
        guard s > 0 else { return 0 }
        let v = Int32(peek(s))
        skip(s)
        return v < Int32(1) << (s - 1) ? v - (Int32(1) << s) + 1 : v
    }

    /// F.2.2.3 DECODE: the next symbol of `t`, or `damaged` for a code it does not hold.
    mutating func symbol(_ t: JPEGHuffman) throws -> Int {
        let e = t.fast[peek(9)]
        if e != 0 { skip(Int(e >> 8)); return Int(e & 0xFF) }
        for length in 10...16 {
            let code = peek(length)
            if code <= t.maxCode[length] { skip(length); return Int(t.values[code + t.offset[length]]) }
        }
        throw CodecError.damaged("no Huffman code in its DHT table matches the next 16 bits")
    }

    /// F.2.2: one sequential block's DC difference and AC run/size symbols into `store` at `base`, zigzag undone.
    mutating func block(_ dc: JPEGHuffman, _ ac: JPEGHuffman, _ pred: inout Int32, _ store: inout [Int32], _ base: Int) throws {
        let s = try symbol(dc)
        guard s <= 15 else { throw CodecError.damaged("DC size \(s) is over 15") }
        pred = pred &+ receive(s)
        store[base] = pred
        var k = 1
        while k < 64 {
            let rs = try symbol(ac), r = rs >> 4, size = rs & 15
            if size == 0 { guard r == 15 else { break }; k += 16; continue }
            k += r
            guard k < 64 else { throw CodecError.damaged("AC run past coefficient 63") }
            store[base + JPEGDecoder.zigzag[k]] = receive(size)
            k += 1
        }
    }
}

extension JPEGDecoder {
    /// The entropy-coded bytes from `at` to the next marker other than RSTm, split at each RSTm, 0xFF 0x00 read as 0xFF.
    mutating func entropy() -> [[UInt8]] {
        var out: [[UInt8]] = [], current: [UInt8] = []
        while at < bytes.count {
            let b = bytes[at]
            if b != 0xFF { current.append(b); at += 1; continue }
            guard at + 1 < bytes.count else { at += 1; break }
            let m = bytes[at + 1]
            if m == 0 { current.append(0xFF) } else if (0xD0...0xD7).contains(m) { out.append(current); current = [] } else { break }
            at += 2
        }
        out.append(current)
        return out
    }

    /// A sequential scan (A.2); every `restart` units the DC predictions are 0.
    mutating func baselineScan(_ scan: JPEGScan, _ intervals: [[UInt8]]) throws {
        var pred = [Int32](repeating: 0, count: scan.parts.count)
        try walk(scan, intervals, restart: { pred = pred.map { _ in 0 } }) { bits, j, store, base in
            guard let dc = scan.parts[j].dc, let ac = scan.parts[j].ac else { throw CodecError.damaged("no DHT \(scan.parts[j].dc == nil ? "DC" : "AC") table") }
            try bits.block(dc, ac, &pred[j], &store, base)
        }
    }

    /// A scan's blocks in coding order (A.2): its MCUs, or one component's own blocks, each passed as the bits, the scan
    /// part, that component's store and the block's offset in it; `reset` runs at each restart interval's start. A
    /// block's `damaged` message gains the SOF component id and the unit, so it can be matched to the file.
    mutating func walk(_ scan: JPEGScan, _ intervals: [[UInt8]], restart reset: () -> Void,
                       _ block: (inout JPEGBits, Int, inout [Int32], Int) throws -> Void) throws {
        guard let f = frame, let lead = scan.parts.first else { return }
        let single = scan.parts.count == 1, first = f.components[lead.index]
        let units = single ? first.blocksX * first.blocksY : f.mcusX * f.mcusY
        var bits = JPEGBits(bytes: []), interval = 0
        for m in 0..<units {
            if m == 0 || (restart > 0 && m % restart == 0) {
                guard interval < intervals.count else { throw CodecError.damaged("restart interval \(interval) missing") }
                bits = JPEGBits(bytes: intervals[interval])
                interval += 1
                reset()
            }
            for (j, part) in scan.parts.enumerated() {
                let c = f.components[part.index]
                let count = single ? 1 : c.h * c.v
                let x0 = single ? m % c.blocksX : m % f.mcusX * c.h, y0 = single ? m / c.blocksX : m / f.mcusX * c.v
                for k in 0..<count {
                    let base = ((y0 + k / c.h) * c.stride + x0 + k % c.h) * 64
                    do { try block(&bits, j, &coefficients[part.index], base) } catch CodecError.damaged(let text) {
                        throw CodecError.damaged("\(text), component \(c.id) unit \(m)")
                    }
                }
            }
            guard !bits.overrun else { throw CodecError.damaged("scan ends at MCU \(m)") }
        }
    }

    /// Entry x * 8 + u is C(u) cos((2x + 1)uπ/16) / 2, so a row pass then a column pass is A.3.3's inverse DCT;
    /// built from cos(mπ/16), m 0...8, by symmetry.
    static let cosines: [Float] = (0..<64).map { (i: Int) -> Float in
        let c: [Float] = [1, 0.980_785_28, 0.923_879_53, 0.831_469_61, 0.707_106_78, 0.555_570_23, 0.382_683_43, 0.195_090_32, 0]
        let m = (2 * (i / 8) + 1) * (i % 8) % 32, f = m > 16 ? 32 - m : m
        return (i % 8 == 0 ? c[4] : 1) * (f <= 8 ? c[f] : -c[16 - f]) / 2
    }

    /// Component `index`'s samples over its padded grid: each block dequantized, inverse transformed, shifted by 128.
    func plane(_ index: Int, _ c: JPEGComponent) throws -> [UInt8] {
        guard let q = quant[c.tq], index < coefficients.count else { throw CodecError.damaged("component \(c.id) uses DQT \(c.tq), not defined") }
        let width = c.stride * 8, store = coefficients[index], t = Self.cosines
        var out = [UInt8](repeating: 0, count: width * c.rows * 8)
        var s = [Float](repeating: 0, count: 64), row = [Float](repeating: 0, count: 64)
        for b in 0..<(c.stride * c.rows) {
            let base = b * 64, origin = (b / c.stride) * 8 * width + (b % c.stride) * 8
            for k in 0..<64 { s[k] = Float(store[base + k]) * q[k] }
            for v in 0..<8 {
                for x in 0..<8 {
                    var sum: Float = 0
                    for u in 0..<8 { sum += t[x * 8 + u] * s[v * 8 + u] }
                    row[v * 8 + x] = sum
                }
            }
            for y in 0..<8 {
                for x in 0..<8 {
                    var sum: Float = 128
                    for v in 0..<8 { sum += t[y * 8 + v] * row[v * 8 + x] }
                    out[origin + y * width + x] = UInt8(min(max(sum.rounded(), 0), 255))
                }
            }
        }
        return out
    }

    /// Linear premultiplied pixels, alpha 1: box upsampling (x * H / Hmax), JFIF YCbCr to RGB, DisplayTransfer's sRGB.
    func pixels() throws -> PixelBuffer {
        guard let f = frame else { throw CodecError.damaged("no SOF") }
        guard let transfer = try? DisplayTransfer(.sRGB) else { throw CodecError.damaged("the sRGB display transfer could not be built") }
        let linear: [Float] = (0...255).map { Float(transfer.decode(UInt8($0), 0, 0).c0) }
        let planes = try f.components.enumerated().map { try plane($0.offset, $0.element) }
        let columns = f.components.map { c in (0..<f.width).map { $0 * c.h / f.hmax } }
        var out = [Float](repeating: 1, count: f.width * f.height * 4)
        func level(_ v: Float) -> Float { linear[Int(min(max(v.rounded(), 0), 255))] }
        for y in 0..<f.height {
            let rows = f.components.map { c in (y * c.v / f.vmax) * c.stride * 8 }
            for x in 0..<f.width {
                let o = (y * f.width + x) * 4, luma = Float(planes[0][rows[0] + columns[0][x]])
                guard planes.count == 3 else { (out[o], out[o + 1], out[o + 2]) = (level(luma), level(luma), level(luma)); continue }
                let cb: Float = Float(planes[1][rows[1] + columns[1][x]]) - 128, cr: Float = Float(planes[2][rows[2] + columns[2][x]]) - 128
                out[o] = level(luma + 1.402 * cr)
                out[o + 1] = level(luma - 0.344_136 * cb - 0.714_136 * cr)
                out[o + 2] = level(luma + 1.772 * cb)
            }
        }
        return PixelBuffer(checkedWidth: f.width, height: f.height, storage: out)
    }
}
