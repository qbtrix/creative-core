// DisplayBytes.swift: PixelBuffer to and from 8-bit RGBA display bytes, the
// one shared way apps show and save a buffer. Bytes are width x height x 4,
// row-major, top row first, straight (unpremultiplied) alpha, color encoded
// with the sRGB or Display P3 transfer curve. All color math goes through
// CoreColor's `DisplayTransfer` (the tables that equal `Color3.converted`
// plus the clamp-and-round byte rule) and the alpha math through
// `RGBA.unpremultiplied` / `RGBA.premultiplied`; nothing here repeats them.
// Decoding reads alpha from a 256-entry table of `Float(byte) / 255`.
// Each call is one pass over storage with no `try` per pixel. Encoding clamps
// each value to 0...1 after the transfer curve and rounds to nearest. A fully
// transparent pixel encodes as 0, 0, 0, 0. A region encodes a rectangle of
// the buffer without cropping a copy first.
import CoreColor

extension PixelBuffer {
    /// The color spaces display bytes may be encoded in.
    public static let displayColorSpaces: [ColorSpace] = [.sRGB, .displayP3]

    /// This buffer as 8-bit straight-alpha RGBA bytes encoded in `colorSpace`.
    /// Throws `RasterError.invalid` when `colorSpace` is not one of
    /// `displayColorSpaces`.
    public func rgba8(colorSpace: ColorSpace = .sRGB) throws -> [UInt8] {
        try rgba8(x: 0, y: 0, width: width, height: height, colorSpace: colorSpace)
    }

    /// The `width x height` rectangle with its top left at (`x`, `y`)
    /// as 8-bit straight-alpha RGBA bytes encoded in `colorSpace`: the same
    /// bytes as `cropped(x:y:width:height:)` then `rgba8(colorSpace:)`, without
    /// the copy. Throws `RasterError.invalid` for a `colorSpace` not in
    /// `displayColorSpaces`, then, as `cropped` does, for a width or height
    /// under 1 or a rectangle not wholly inside the buffer.
    public func rgba8(x: Int, y: Int, width regionWidth: Int, height regionHeight: Int,
                      colorSpace: ColorSpace = .sRGB) throws -> [UInt8] {
        let encoder = try Self.displayTransfer(colorSpace)
        try checkedRegion(x: x, y: y, width: regionWidth, height: regionHeight)
        let c = Self.channels
        let rowCount = regionWidth * c
        let count = regionHeight * rowCount
        // In sRGB, ±infinity encodes as the largest finite values do; only the
        // P3 matrix needs `finite`, or it would turn infinity - infinity into NaN.
        let p3 = encoder.space == .displayP3
        // Every byte is written below, so the array starts uninitialized.
        return components.withUnsafeBufferPointer { source in
            [UInt8](unsafeUninitializedCapacity: count) { out, initialized in
                for row in 0..<regionHeight {
                    let from = ((y + row) * width + x) * c
                    let to = row * rowCount
                    for i in stride(from: 0, to: rowCount, by: c) {
                        let s = RGBA(r: source[from + i], g: source[from + i + 1], b: source[from + i + 2],
                                     a: source[from + i + 3]).unpremultiplied()
                        let color = p3 ? Color3(Self.finite(s.r), Self.finite(s.g), Self.finite(s.b))
                            : Color3(Double(s.r), Double(s.g), Double(s.b))
                        let (r, g, b) = encoder.encode(color)
                        out[to + i] = r
                        out[to + i + 1] = g
                        out[to + i + 2] = b
                        out[to + i + 3] = DisplayTransfer.byte(Double(s.a))
                    }
                }
                initialized = count
            }
        }
    }

    /// A buffer from 8-bit straight-alpha RGBA bytes encoded in `colorSpace`,
    /// decoded to linear light and premultiplied. Throws `RasterError.invalid`
    /// for an invalid size (see `validatedSize`), a byte count other than
    /// `width * height * 4`, or a `colorSpace` not in `displayColorSpaces`.
    public init(rgba8 bytes: [UInt8], width: Int, height: Int, colorSpace: ColorSpace = .sRGB) throws {
        let pixels = try Self.validatedSize(width: width, height: height)
        let decoder = try Self.displayTransfer(colorSpace)
        // No overflow: validatedSize checked pixels * channels.
        guard bytes.count == pixels * Self.channels else {
            throw RasterError.invalid("rgba8 has \(bytes.count) bytes; \(width)x\(height) needs \(pixels * Self.channels)")
        }
        let c = Self.channels
        // Every component is written below, so the array starts uninitialized.
        // A byte always indexes 0...255, so the alpha table is read unchecked.
        let storage = bytes.withUnsafeBufferPointer { src in
            Self.alphaTable.withUnsafeBufferPointer { alpha in
                [Float](unsafeUninitializedCapacity: src.count) { out, initialized in
                    for i in stride(from: 0, to: src.count, by: c) {
                        let linear = decoder.decode(src[i], src[i + 1], src[i + 2])
                        let p = RGBA(r: Float(linear.c0), g: Float(linear.c1), b: Float(linear.c2),
                                     a: alpha[Int(src[i + 3])]).premultiplied()
                        out[i] = p.r
                        out[i + 1] = p.g
                        out[i + 2] = p.b
                        out[i + 3] = p.a
                    }
                    initialized = src.count
                }
            }
        }
        self.init(checkedWidth: width, height: height, storage: storage)
    }

    /// Straight alpha for each byte: entry b is `Float(b) / 255`.
    private static let alphaTable: [Float] = (0...255).map { Float($0) / 255 }

    /// The display tables for `colorSpace`, or `RasterError.invalid` when it
    /// is not in `displayColorSpaces`, the spaces `DisplayTransfer` accepts.
    private static func displayTransfer(_ colorSpace: ColorSpace) throws -> DisplayTransfer {
        guard let transfer = try? DisplayTransfer(colorSpace) else {
            throw RasterError.invalid("color space \(colorSpace.rawValue): display bytes must be sRGB or displayP3")
        }
        return transfer
    }

    /// A straight component as a finite Double. Unpremultiplying a tiny alpha
    /// can overflow Float to infinity; the clamped encode cannot tell the
    /// largest finite value from it.
    private static func finite(_ v: Float) -> Double {
        Double(min(max(v, -.greatestFiniteMagnitude), .greatestFiniteMagnitude))
    }
}
