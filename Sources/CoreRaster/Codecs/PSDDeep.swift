// PSDDeep.swift: channel depth and the embedded profile for PSDRead and
// PSDWrite, from the published PSD specification. Samples are 8 or 16 bits
// (16-bit ones big-endian); RLE runs over row bytes. The ICC profile is image
// resource 1039 (`8BIM`, id, Pascal name and data, each padded to even).
// Invariants: a plane holds `count * bytes` bytes before any sample is read;
// every resource length is checked against its section, and a profile the
// ICC reader refuses throws `unsupported`; 8-bit output is byte-for-byte the
// old one; 16-bit output reopens == (nearest sample after unpremultiplying).
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

    /// Red, green, blue and alpha planes of premultiplied linear pixels, `bytes` per sample.
    func colorPlanes(_ buffer: PixelBuffer) -> [[UInt8]] {
        let components = buffer.components, count = components.count / 4, table = linear
        var planes = [[UInt8]](repeating: [UInt8](repeating: 0, count: count * bytes), count: 4)
        for i in 0..<count {
            let alpha = quantized(components[i * 4 + 3])
            put(alpha, into: &planes[3], at: i)
            guard alpha > 0 else { continue }
            let a = Float(alpha) / Float(maxSample)
            for c in 0..<3 { put(PSD.nearest(components[i * 4 + c] / a, in: table), into: &planes[c], at: i) }
        }
        return planes
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

    /// The index whose entry in the ascending `table` is nearest `value`, by binary search.
    static func nearest(_ value: Float, in table: [Float]) -> Int {
        var low = 0, high = table.count - 1
        while low < high {
            let mid = (low + high) / 2
            if table[mid] < value { low = mid + 1 } else { high = mid }
        }
        if low > 0, value - table[low - 1] <= table[low] - value { low -= 1 }
        return low
    }

    /// The profile in an image resources section (resource 1039), or nil when it has none.
    /// Other resources are skipped by length; a truncated block throws `damaged`.
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
            let icc = Data(try block.bytes(size))
            do { profile = try ColorProfile(iccData: icc) } catch {
                throw CodecError.unsupported("the embedded colour profile: \(error)")
            }
        }
        return profile
    }

    /// The image resources section's contents for `profile`: empty for nil, else resource 1039 holding its ICC bytes.
    /// The file is RGB, so a gray profile throws `unsupported`, as does one the ICC writer refuses.
    static func imageResources(_ profile: ColorProfile?) throws -> [UInt8] {
        guard let profile else { return [] }
        guard !profile.isGray else { throw CodecError.unsupported("gray colour profile \"\(profile.name)\" on an RGB file") }
        let icc: Data
        do { icc = try profile.iccData() } catch {
            throw CodecError.unsupported("colour profile \"\(profile.name)\": \(error)")
        }
        var w = PSDByteWriter()
        w.ascii("8BIM"); w.u16(1039); w.bytes += [0, 0] // an empty name, padded to even
        try w.length(icc.count)
        w.bytes += icc + (icc.count % 2 == 1 ? [0] : [])
        return w.bytes
    }
}
