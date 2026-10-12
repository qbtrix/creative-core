// DisplayBytes.swift: PixelBuffer to and from 8-bit RGBA display bytes, the
// one shared way apps show and save a buffer. Bytes are width x height x 4,
// row-major, top row first, straight (unpremultiplied) alpha, color encoded
// with the sRGB or Display P3 transfer curve. All color math goes through
// CoreColor's `Color3.converted` and the alpha math through
// `RGBA.unpremultiplied` / `RGBA.premultiplied`; nothing here repeats them.
// Encoding clamps each value to 0...1 after the transfer curve (the curve is
// monotonic and fixes 0 and 1, so this equals clamping before it) and rounds
// to nearest. A fully transparent pixel encodes as 0, 0, 0, 0.
import CoreColor

extension PixelBuffer {
    /// The color spaces display bytes may be encoded in.
    public static let displayColorSpaces: [ColorSpace] = [.sRGB, .displayP3]

    /// This buffer as 8-bit straight-alpha RGBA bytes encoded in `colorSpace`.
    /// Throws `RasterError.invalid` when `colorSpace` is not one of
    /// `displayColorSpaces`.
    public func rgba8(colorSpace: ColorSpace = .sRGB) throws -> [UInt8] {
        try Self.checkDisplay(colorSpace)
        let c = components
        var bytes = [UInt8](repeating: 0, count: c.count)
        for i in stride(from: 0, to: c.count, by: Self.channels) {
            let s = RGBA(r: c[i], g: c[i + 1], b: c[i + 2], a: c[i + 3]).unpremultiplied()
            let linear = Color3(Self.finite(s.r), Self.finite(s.g), Self.finite(s.b))
            let encoded = try Self.convert(linear, from: .linearSRGB, to: colorSpace).clampedToUnit()
            bytes[i] = Self.byte(encoded.c0)
            bytes[i + 1] = Self.byte(encoded.c1)
            bytes[i + 2] = Self.byte(encoded.c2)
            bytes[i + 3] = Self.byte(min(max(Double(s.a), 0), 1))
        }
        return bytes
    }

    /// A buffer from 8-bit straight-alpha RGBA bytes encoded in `colorSpace`,
    /// decoded to linear light and premultiplied. Throws `RasterError.invalid`
    /// for an invalid size (see `validatedSize`), a byte count other than
    /// `width * height * 4`, or a `colorSpace` not in `displayColorSpaces`.
    public init(rgba8 bytes: [UInt8], width: Int, height: Int, colorSpace: ColorSpace = .sRGB) throws {
        let pixels = try Self.validatedSize(width: width, height: height)
        try Self.checkDisplay(colorSpace)
        // No overflow: validatedSize checked pixels * channels.
        guard bytes.count == pixels * Self.channels else {
            throw RasterError.invalid("rgba8 has \(bytes.count) bytes; \(width)x\(height) needs \(pixels * Self.channels)")
        }
        var storage = [Float](repeating: 0, count: bytes.count)
        for i in stride(from: 0, to: bytes.count, by: Self.channels) {
            let encoded = Color3(Double(bytes[i]) / 255, Double(bytes[i + 1]) / 255, Double(bytes[i + 2]) / 255)
            let linear = try Self.convert(encoded, from: colorSpace, to: .linearSRGB)
            let p = RGBA(r: Float(linear.c0), g: Float(linear.c1), b: Float(linear.c2),
                         a: Float(bytes[i + 3]) / 255).premultiplied()
            storage[i] = p.r
            storage[i + 1] = p.g
            storage[i + 2] = p.b
            storage[i + 3] = p.a
        }
        self.init(checkedWidth: width, height: height, storage: storage)
    }

    private static func checkDisplay(_ colorSpace: ColorSpace) throws {
        guard displayColorSpaces.contains(colorSpace) else {
            throw RasterError.invalid("color space \(colorSpace.rawValue): display bytes must be sRGB or displayP3")
        }
    }

    /// `Color3.converted`, with its `ColorError` mapped to `RasterError`.
    private static func convert(_ color: Color3, from source: ColorSpace, to target: ColorSpace) throws -> Color3 {
        do {
            return try color.converted(from: source, to: target)
        } catch {
            throw RasterError.invalid("display bytes conversion failed: \(error)")
        }
    }

    /// A straight component as a finite Double. Unpremultiplying a tiny alpha
    /// can overflow Float to infinity; the clamped encode cannot tell the
    /// largest finite value from it.
    private static func finite(_ v: Float) -> Double {
        Double(min(max(v, -.greatestFiniteMagnitude), .greatestFiniteMagnitude))
    }

    /// A value in 0...1 rounded to the nearest byte.
    private static func byte(_ v: Double) -> UInt8 {
        UInt8((v * 255).rounded())
    }
}
