// PSDDeep.swift: channel depth and the embedded profile for PSDRead and
// PSDWrite, from the published PSD specification. Samples are 8 or 16 bits
// (16-bit ones big-endian); RLE runs over row bytes. The ICC profile is image
// resource 1039 (`8BIM`, id, Pascal name and data, each padded to even).
// Invariants: a plane holds `count * bytes` bytes before any sample is read;
// every resource length is checked against its section (`damaged`), and a
// profile the ICC reader refuses is dropped, so the file opens without one;
// a gray profile writes a grayscale file, and a pixel whose stored red, green
// and blue differ then throws `unsupported`; 8-bit output is byte-for-byte the
// old one; 16-bit output reopens == (nearest sample after unpremultiplying).
// `nearest` with spans searches only a 0..<1 value's bucket of the table and
// must return what the whole-table search returns, so the fast save writes
// the same bytes.
import CoreColor
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Bits per channel of a PSD's samples. Opacity and the mask default stay one byte at either depth.
enum PSDDepth: Int, Sendable {
    case eight = 8, sixteen = 16

    /// The depth for a header's or an image's bits per channel; any other throws `unsupported`.
    init(bits: Int) throws {
        guard let depth = PSDDepth(rawValue: bits) else { throw CodecError.unsupported("\(bits)-bit channels") }
        self = depth
    }
    /// Bytes per sample.
    var bytes: Int { self == .eight ? 1 : 2 }
    /// The largest sample, which stands for 1.
    var maxSample: Int { self == .eight ? 255 : 65_535 }
    /// Each encoded sRGB sample's linear light.
    var linear: [Float] { self == .eight ? PSD.linear : PSD.linear16 }
    /// `linear`'s bucket spans for `PSD.nearest(_:in:spans:)`.
    var spans: [Int] { self == .eight ? PSD.spans8 : PSD.spans16 }
    /// Sample `i` of a plane holding at least `(i + 1) * bytes` bytes.
    func sample(_ plane: [UInt8], _ i: Int) -> Int {
        guard self == .sixteen else { return Int(plane[i]) }
        return Int(plane[i * 2]) << 8 | Int(plane[i * 2 + 1])
    }
    /// Sample `i` as a fraction of `maxSample`.
    func fraction(_ plane: [UInt8], _ i: Int) -> Float { Float(sample(plane, i)) / Float(maxSample) }
    /// Stores `value` (0...maxSample) as sample `i`, high byte first.
    func put(_ value: Int, into plane: inout [UInt8], at i: Int) {
        guard self == .sixteen else { plane[i] = UInt8(truncatingIfNeeded: value); return }
        plane[i * 2] = UInt8(truncatingIfNeeded: value >> 8)
        plane[i * 2 + 1] = UInt8(truncatingIfNeeded: value)
    }
    /// A 0...1 value as a sample, rounded to nearest; NaN and below 0 are 0.
    func quantized(_ value: Float) -> Int {
        guard self == .sixteen else { return Int(PSD.fraction(value)) }
        let scaled = (value * 65_535).rounded()
        return scaled > 0 ? Int(min(scaled, 65_535)) : 0
    }

    /// Red, green, blue and alpha planes of premultiplied linear pixels, `bytes` per sample,
    /// written planar into one buffer through unsafe pointers (the 12 MP save's hot loop).
    func colorPlanes(_ buffer: PixelBuffer) -> [[UInt8]] {
        let components = buffer.components, count = components.count / 4, table = linear, spans = self.spans
        let size = count * bytes, wide = self == .sixteen, top = Float(maxSample)
        var out = [UInt8](repeating: 0, count: size * 4)
        components.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                func store(_ value: Int, _ plane: Int, _ i: Int) {
                    if wide {
                        dst[plane * size + i * 2] = UInt8(truncatingIfNeeded: value >> 8)
                        dst[plane * size + i * 2 + 1] = UInt8(truncatingIfNeeded: value)
                    } else {
                        dst[plane * size + i] = UInt8(truncatingIfNeeded: value)
                    }
                }
                for i in 0..<count {
                    let alpha = quantized(src[i * 4 + 3])
                    store(alpha, 3, i)
                    guard alpha > 0 else { continue }
                    let a = Float(alpha) / top
                    for c in 0..<3 { store(PSD.nearest(src[i * 4 + c] / a, in: table, spans: spans), c, i) }
                }
            }
        }
        return (0..<4).map { Array(out[$0 * size..<($0 + 1) * size]) }
    }
    /// `colorPlanes`, folded to grey and alpha when `gray`. A pixel whose stored
    /// red, green and blue samples differ cannot be grey, so it throws `unsupported`.
    func colorPlanes(_ buffer: PixelBuffer, gray: Bool, _ what: String) throws -> [[UInt8]] {
        let planes = colorPlanes(buffer)
        guard gray else { return planes }
        guard planes[0] == planes[1], planes[1] == planes[2] else {
            throw CodecError.unsupported("\(what) is not grey, so it cannot be saved with a gray colour profile")
        }
        return [planes[0], planes[3]]
    }
    /// A mask's coverage as one plane, `bytes` per sample.
    func maskPlane(_ mask: Mask) -> [UInt8] {
        var plane = [UInt8](repeating: 0, count: mask.width * mask.height * bytes)
        for i in 0..<mask.width * mask.height {
            put(quantized((try? mask.coverage(x: i % mask.width, y: i / mask.width)) ?? 0), into: &plane, at: i)
        }
        return plane
    }
}

extension PSD {
    /// Encoded 16-bit sRGB to linear light.
    static let linear16: [Float] = (0..<65_536).map { Float(TransferCurve.decode(Double($0) / 65_535)) }

    /// Buckets per unit in the spans tables; a power of two, so `value * spanCount` is exact.
    static let spanCount = 65_536
    /// For each bucket edge b / `spanCount` (b in 0...spanCount), `firstAtLeast` of it in the table.
    /// A value in bucket b has its `firstAtLeast` in `spans[b]...spans[b + 1]`, since that index
    /// never decreases as the value grows.
    static func spans(_ table: [Float]) -> [Int] {
        (0...spanCount).map { firstAtLeast(Float($0) / Float(spanCount), in: table, 0, table.count - 1) }
    }
    static let spans8 = spans(linear), spans16 = spans(linear16)

    /// The first index in `low...high` of the ascending `table` whose entry is at least `value`, else `high`.
    static func firstAtLeast(_ value: Float, in table: [Float], _ low: Int, _ high: Int) -> Int {
        var low = low, high = high
        while low < high {
            let mid = (low + high) / 2
            if table[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// The index whose entry in the ascending `table` is nearest `value`, ties to the lower index.
    /// `spans` is `spans(table)`: a 0..<1 value searches only its bucket, anything else
    /// (1 and over, negative, NaN) the whole table.
    static func nearest(_ value: Float, in table: [Float], spans: [Int]) -> Int {
        var low: Int
        if value >= 0, value < 1 {
            let bucket = Int(value * Float(spanCount))
            low = firstAtLeast(value, in: table, spans[bucket], spans[bucket + 1])
        } else {
            low = firstAtLeast(value, in: table, 0, table.count - 1)
        }
        if low > 0, value - table[low - 1] <= table[low] - value { low -= 1 }
        return low
    }

    /// The profile in an image resources section (resource 1039), or nil when it has none.
    /// Other resources are skipped by length; a truncated block throws `damaged`. A profile
    /// `ColorProfile(iccData:)` refuses (LUT-based, CMYK, a printer class, damaged bytes) is
    /// dropped: the file opens with no profile, as it did before profiles were read.
    static func profile(in resources: inout ByteReader) throws -> ColorProfile? {
        var profile: ColorProfile?
        while !resources.isAtEnd {
            let signature = try resources.bytes(4)
            let id = try resources.u16()
            let nameLength = Int(try resources.u8())
            try resources.skip(nameLength + (nameLength + 1) % 2) // the length byte and name pad to even
            let size = try resources.length32()
            var block = try resources.reader(size)
            try resources.skip(min(size % 2, resources.remaining)) // data pads to even; a last block may not
            guard signature == Array("8BIM".utf8), id == 1039 else { continue }
            profile = try? ColorProfile(iccData: Data(try block.bytes(size)))
        }
        return profile
    }

    /// The image resources section's contents for `profile`: empty for nil, else resource 1039 holding its ICC bytes.
    /// A profile the ICC writer refuses throws `unsupported`.
    static func imageResources(_ profile: ColorProfile?) throws -> [UInt8] {
        guard let profile else { return [] }
        let icc = try CodecError.profileData(profile)
        var w = PSDByteWriter()
        w.ascii("8BIM"); w.u16(1039); w.bytes += [0, 0] // an empty name, padded to even
        try w.length(icc.count)
        w.bytes += icc + (icc.count % 2 == 1 ? [0] : [])
        return w.bytes
    }
}

extension CodecError {
    /// `profile.iccData()`, or `unsupported` naming the profile and the ICC writer's reason.
    static func profileData(_ profile: ColorProfile) throws -> Data {
        do { return try profile.iccData() } catch let ColorError.invalid(why) {
            throw CodecError.unsupported("the colour profile \"\(profile.name)\": \(why)")
        }
    }
}
