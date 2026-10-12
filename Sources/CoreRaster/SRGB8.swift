// SRGB8.swift: the one display and file conversion of a PixelBuffer, to and
// from 8-bit RGBA bytes: sRGB-encoded, straight (unpremultiplied) alpha,
// row-major, top row first, 4 bytes per pixel. Export unpremultiplies
// (`RGBA.unpremultiplied`), clamps to 0...1, applies CoreColor's sRGB curve and
// rounds; a pixel whose alpha byte is 0 exports as four zero bytes. Import
// decodes with the same curve and premultiplies (`RGBA.premultiplied`). The
// transfer math lives only in CoreColor; this file never copies it.
import CoreColor

extension PixelBuffer {
    /// The buffer as 8-bit sRGB RGBA bytes with straight alpha, `width * height * 4`
    /// long. Components outside 0...1 clamp. Throws `RasterError.invalid` only
    /// if CoreColor rejects a clamped color, which finite input never does.
    public func sRGB8Bytes() throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: components.count)
        let source = components
        for i in stride(from: 0, to: source.count, by: Self.channels) {
            let p = RGBA(r: source[i], g: source[i + 1], b: source[i + 2], a: source[i + 3]).unpremultiplied()
            let alpha = Self.byte(Double(p.a))
            guard alpha != 0 else { continue }
            let linear = Color3(Double(p.r), Double(p.g), Double(p.b)).clampedToUnit()
            let encoded = try Self.convert(linear, from: .linearSRGB, to: .sRGB)
            bytes[i] = Self.byte(encoded.c0)
            bytes[i + 1] = Self.byte(encoded.c1)
            bytes[i + 2] = Self.byte(encoded.c2)
            bytes[i + 3] = alpha
        }
        return bytes
    }

    /// A buffer from 8-bit sRGB RGBA bytes with straight alpha (the layout
    /// `sRGB8Bytes` writes). Throws `RasterError.invalid` for an invalid size
    /// (see `validatedSize`) or a byte count other than `width * height * 4`.
    public init(width: Int, height: Int, sRGB8Bytes bytes: [UInt8]) throws {
        let pixels = try Self.validatedSize(width: width, height: height)
        let count = pixels * Self.channels
        guard bytes.count == count else {
            throw RasterError.invalid("size \(width)x\(height) needs \(count) bytes, got \(bytes.count)")
        }
        // Every byte level decoded once; the curve is per channel.
        let linear = try (0...255).map { level -> Float in
            let v = Double(level) / 255
            return Float(try Self.convert(Color3(v, v, v), from: .sRGB, to: .linearSRGB).c0)
        }
        var storage = [Float](repeating: 0, count: count)
        for i in stride(from: 0, to: count, by: Self.channels) {
            let straight = RGBA(r: linear[Int(bytes[i])], g: linear[Int(bytes[i + 1])],
                                b: linear[Int(bytes[i + 2])], a: Float(bytes[i + 3]) / 255)
            let p = straight.premultiplied()
            storage[i] = p.r
            storage[i + 1] = p.g
            storage[i + 2] = p.b
            storage[i + 3] = p.a
        }
        self.init(checkedWidth: width, height: height, storage: storage)
    }

    /// A unit value clamped to 0...1 and rounded to the nearest of 256 levels.
    private static func byte(_ unit: Double) -> UInt8 {
        UInt8((min(max(unit, 0), 1) * 255).rounded())
    }

    /// CoreColor's conversion, with its error mapped to this module's.
    private static func convert(_ c: Color3, from source: ColorSpace, to target: ColorSpace) throws -> Color3 {
        do {
            return try c.converted(from: source, to: target)
        } catch {
            throw RasterError.invalid("sRGB conversion failed: \(error)")
        }
    }
}
