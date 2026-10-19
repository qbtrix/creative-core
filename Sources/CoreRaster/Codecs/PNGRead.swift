// PNGRead.swift: the reader behind `PNG.info` and `PNG.read`, from the W3C
// PNG specification (third edition) only. Chunks are CRC-checked (5.3): IHDR
// first, PLTE and tRNS kept, IDATs joined, IEND last, an unknown critical
// chunk unsupported. Invariants: sizes come from IHDR and pass `PNG.maxSide`
// and `PixelBuffer.maxPixels` before anything is inflated or allocated;
// inflate is capped at the filtered bytes IHDR implies and must fill them, so
// every row index below lies inside the inflated bytes; sample values index
// tables sized for their depth, and palette indices are checked.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One Adam7 pass (8.2): first column, first row, column step, row step.
typealias PNGPass = (x: Int, y: Int, dx: Int, dy: Int)

extension PNG {
    static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    static let adam7: [PNGPass] = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
    /// The depths IHDR allows per colour type (11.2.2, table 11.1).
    static let depths: [Int: [Int]] = [0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16]]
    /// Samples per pixel per colour type (6.1).
    static let samples: [Int: Int] = [0: 1, 2: 3, 3: 1, 4: 2, 6: 4]

    static func damaged(_ text: String) -> CodecError { .damaged("PNG: " + text) }

    /// A reader past the signature and IHDR, and IHDR's fields.
    static func header(_ data: Data) throws -> (ByteReader, PNGInfo) {
        var reader = ByteReader(data)
        guard data.count >= 8, try reader.bytes(8) == signature else { throw CodecError.notThisFormat }
        let (type, _, body) = try chunk(&reader)
        guard type == "IHDR" else { throw damaged("IHDR is not the first chunk") }
        guard body.count == 13 else { throw damaged("IHDR holds \(body.count) bytes, not 13") }
        var r = ByteReader(body)
        let width = try r.length32(), height = try r.length32()
        let depth = Int(try r.u8()), colorType = Int(try r.u8())
        let compression = try r.u8(), filter = try r.u8(), interlace = try r.u8()
        guard width > 0, height > 0 else { throw damaged("zero width or height (\(width)x\(height))") }
        guard width <= maxSide, height <= maxSide else { throw CodecError.tooLarge("PNG: \(width)x\(height) pixels: sides are at most \(maxSide)") }
        guard (try? PixelBuffer.validatedSize(width: width, height: height)) != nil else {
            throw CodecError.tooLarge("PNG: \(width)x\(height) pixels: over PixelBuffer.maxPixels (\(PixelBuffer.maxPixels))")
        }
        guard depths[colorType]?.contains(depth) == true else { throw damaged("depth \(depth) with colour type \(colorType)") }
        guard compression == 0, filter == 0, interlace <= 1 else {
            throw damaged("compression method \(compression), filter method \(filter), interlace method \(interlace): only 0, 0 and 0 or 1")
        }
        return (reader, PNGInfo(width: width, height: height, bitDepth: depth, colorType: colorType, interlaced: interlace == 1))
    }

    /// The next chunk's type as text (`typeName`), whether it is critical (5.4: bit 5 of its first
    /// byte clear), and its body, its CRC checked.
    static func chunk(_ reader: inout ByteReader) throws -> (String, Bool, [UInt8]) {
        let length = try reader.length32()
        guard length <= 0x7FFF_FFFF else { throw damaged("chunk length \(length) over 2^31-1") }
        let typed = try reader.bytes(try ByteReader.adding(length, 4))
        let type = typeName(typed.prefix(4))
        guard try reader.u32() == ByteReader.crc32(typed) else { throw damaged("\(type) chunk CRC mismatch") }
        return (type, typed.first.map { $0 & 0x20 == 0 } == true, Array(typed.dropFirst(4)))
    }

    /// A chunk type as text: its four letters when they are ASCII letters (5.4), else hex such as `0x00FF4142`.
    static func typeName(_ bytes: ArraySlice<UInt8>) -> String {
        guard !bytes.allSatisfy({ (0x41...0x5A).contains($0 & 0xDF) }) else { return String(decoding: bytes, as: UTF8.self) }
        let digits = Array("0123456789ABCDEF")
        return "0x" + String(bytes.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0x0F)]] })
    }

    /// Pixels in a pass along a side of `size`, starting at `start` with `step`.
    static func count(_ size: Int, _ start: Int, _ step: Int) -> Int { size > start ? (size - start + step - 1) / step : 0 }

    static func decode(_ data: Data) throws -> PixelBuffer {
        var (reader, info) = try header(data)
        let pixels = info.width * info.height  // `header` held it to `PixelBuffer.maxPixels`
        var palette: [UInt8] = [], alpha: [UInt8]?, stream: [UInt8] = []
        chunks: while true {
            guard !reader.isAtEnd else { throw damaged("file ends before IEND") }
            let (type, critical, body) = try chunk(&reader)
            switch type {
            case "IEND": break chunks
            case "IDAT": stream += body
            case "PLTE": palette = body
            case "tRNS": alpha = body
            case "IHDR": throw damaged("a second IHDR")
            default: if critical { throw CodecError.unsupported("PNG: unknown critical chunk \(type)") }
            }
        }
        guard !stream.isEmpty else { throw damaged("no IDAT chunk") }
        let format = try PNGSamples(info, palette: palette, alpha: alpha)
        let passes: [PNGPass] = info.interlaced ? adam7 : [(0, 0, 1, 1)]
        let bitsPerPixel = format.channels * info.bitDepth
        var total = 0
        for p in passes {
            let w = count(info.width, p.x, p.dx), h = count(info.height, p.y, p.dy)
            guard w > 0, h > 0 else { continue }
            total = try ByteReader.adding(total, try ByteReader.multiplying(h, 1 + (w * bitsPerPixel + 7) / 8))
        }
        // Inflate names neither PNG nor IDAT, and its `tooLarge` here means damaged data, not a size limit.
        var raw: [UInt8]
        do { raw = [UInt8](try Inflate.zlib(Data(stream), limit: total)) } catch CodecError.tooLarge(_) {
            throw damaged("image data inflates past the \(total) bytes IHDR implies")
        } catch CodecError.damaged(let text) { throw damaged("IDAT " + text) }
        guard raw.count == total else { throw damaged("image data holds \(raw.count) bytes, not \(total)") }
        var storage = [Float](repeating: 0, count: pixels * PixelBuffer.channels)
        let bpp = max(1, bitsPerPixel / 8)
        var at = 0
        for p in passes {
            let w = count(info.width, p.x, p.dx), h = count(info.height, p.y, p.dy), rowBytes = (w * bitsPerPixel + 7) / 8
            guard w > 0, h > 0 else { continue }
            for row in 0..<h {
                try unfilter(&raw, type: raw[at], start: at + 1, count: rowBytes, prior: row > 0 ? at - rowBytes : -1, bpp: bpp)
                var out = ((p.y + row * p.dy) * info.width + p.x) * PixelBuffer.channels
                for i in 0..<w {
                    let c = try format.pixel(raw, at + 1, i)
                    storage[out] = c.r
                    storage[out + 1] = c.g
                    storage[out + 2] = c.b
                    storage[out + 3] = c.a
                    out += p.dx * PixelBuffer.channels
                }
                at += rowBytes + 1
            }
        }
        return PixelBuffer(checkedWidth: info.width, height: info.height, storage: storage)
    }

    /// The Paeth predictor (9.4): ties go to a, then b.
    @inline(__always) static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        return pa <= pb && pa <= pc ? a : (pb <= pc ? b : c)
    }

    /// Undoes filter `type` (9.2) on the `count` bytes at `start`, in place; `prior` is the previous
    /// row's start in this pass, or -1 for its first row, whose prior bytes count as 0.
    static func unfilter(_ raw: inout [UInt8], type: UInt8, start: Int, count: Int, prior: Int, bpp: Int) throws {
        guard type != 0 else { return }
        guard type <= 4 else { throw damaged("filter type \(type)") }
        for i in 0..<count {
            let a = i >= bpp ? Int(raw[start + i - bpp]) : 0
            let b = prior >= 0 ? Int(raw[prior + i]) : 0
            let c = prior >= 0 && i >= bpp ? Int(raw[prior + i - bpp]) : 0
            let predictor: Int
            switch type {
            case 1: predictor = a
            case 2: predictor = b
            case 3: predictor = (a + b) >> 1
            default: predictor = paeth(a, b, c)
            }
            raw[start + i] &+= UInt8(truncatingIfNeeded: predictor)
        }
    }
}

/// How one PNG's samples become premultiplied linear pixels: the sRGB curve as
/// a table per sample value, the palette already converted, the tRNS key.
struct PNGSamples {
    let colorType: Int, depth: Int, channels: Int
    /// Linear light per encoded sample value, 0...2^depth - 1.
    let colour: [Float]
    /// Palette entries as premultiplied linear RGBA, four Floats each.
    let palette: [Float]
    /// tRNS key samples (grey uses the first), -1 when none.
    let key: [Int]
    let top: Double

    init(_ info: PNGInfo, palette bytes: [UInt8], alpha: [UInt8]?) throws {
        colorType = info.colorType
        depth = info.bitDepth
        channels = PNG.samples[info.colorType] ?? 1
        let top = (1 << depth) - 1
        self.top = Double(top)
        colour = depth == 16 ? PSD.linear16 : (0...top).map { PSD.linear[$0 * 255 / top] }
        var table: [Float] = [], key = [-1, -1, -1]
        if colorType == 3 {
            let entries = bytes.count / 3, opacity = alpha ?? []
            guard bytes.count % 3 == 0, (1...256).contains(entries) else { throw PNG.damaged("palette image without a valid PLTE") }
            guard opacity.count <= entries else { throw PNG.damaged("tRNS longer than PLTE") }
            for e in 0..<entries {
                let a: Float = e < opacity.count ? Float(Double(opacity[e]) / 255) : 1
                table += [PSD.linear[Int(bytes[3 * e])] * a, PSD.linear[Int(bytes[3 * e + 1])] * a, PSD.linear[Int(bytes[3 * e + 2])] * a, a]
            }
        } else if let alpha, colorType == 0 || colorType == 2 {
            guard alpha.count == 2 * channels else { throw PNG.damaged("tRNS of \(alpha.count) bytes") }
            for s in 0..<channels { key[s] = Int(alpha[2 * s]) << 8 | Int(alpha[2 * s + 1]) }
        }
        palette = table
        self.key = key
    }

    /// Sample `k` of the row whose bytes start at `start` (7.2: high bits first, 16-bit big-endian).
    @inline(__always) func sample(_ raw: [UInt8], _ start: Int, _ k: Int) -> Int {
        switch depth {
        case 8: return Int(raw[start + k])
        case 16: return Int(raw[start + 2 * k]) << 8 | Int(raw[start + 2 * k + 1])
        default:
            let bit = k * depth
            return (Int(raw[start + (bit >> 3)]) >> (8 - depth - (bit & 7))) & ((1 << depth) - 1)
        }
    }

    /// Pixel `i` of the row at `start`, premultiplied linear.
    @inline(__always) func pixel(_ raw: [UInt8], _ start: Int, _ i: Int) throws -> RGBA {
        let k = i * channels, v = sample(raw, start, k)
        switch colorType {
        case 0:
            let a: Float = v == key[0] ? 0 : 1, g = colour[v] * a
            return RGBA(r: g, g: g, b: g, a: a)
        case 2:
            let g = sample(raw, start, k + 1), b = sample(raw, start, k + 2)
            let a: Float = v == key[0] && g == key[1] && b == key[2] ? 0 : 1
            return RGBA(r: colour[v] * a, g: colour[g] * a, b: colour[b] * a, a: a)
        case 3:
            guard 4 * v < palette.count else { throw PNG.damaged("palette index \(v) past PLTE") }
            return RGBA(r: palette[4 * v], g: palette[4 * v + 1], b: palette[4 * v + 2], a: palette[4 * v + 3])
        case 4:
            let a = Float(Double(sample(raw, start, k + 1)) / top), g = colour[v] * a
            return RGBA(r: g, g: g, b: g, a: a)
        default:
            let a = Float(Double(sample(raw, start, k + 3)) / top)
            return RGBA(r: colour[v] * a, g: colour[sample(raw, start, k + 1)] * a, b: colour[sample(raw, start, k + 2)] * a, a: a)
        }
    }
}
