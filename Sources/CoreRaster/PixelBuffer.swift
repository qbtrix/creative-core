// PixelBuffer.swift: CoreRaster's base image type. A width x height grid of
// RGBA pixels stored as Float32, in linear light with premultiplied alpha.
// Invariants a reader must keep: width and height are at least 1, the pixel
// count is at most `maxPixels`, `storage.count == width * height * 4`, and every
// stored component is finite. Every size goes through `validatedSize`, and every
// write through `setPixel`, `copyRows`, `updateRow` or
// `init(checkedWidth:height:storage:)` (whose callers in this module check the
// same rules), so the invariants hold for any value of this type.

/// One pixel: four Float32 components. Inside a `PixelBuffer` the color is
/// premultiplied by alpha; the helpers convert to and from straight alpha.
public struct RGBA: Equatable, Hashable, Sendable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public init(r: Float, g: Float, b: Float, a: Float) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Transparent black, all components zero.
    public static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)

    /// True when no component is NaN or infinite.
    public var isFinite: Bool {
        r.isFinite && g.isFinite && b.isFinite && a.isFinite
    }

    /// Straight alpha to premultiplied: color components times alpha.
    public func premultiplied() -> RGBA {
        RGBA(r: r * a, g: g * a, b: b * a, a: a)
    }

    /// Premultiplied to straight alpha: color components divided by alpha.
    /// A fully transparent pixel has no recoverable color, so alpha 0 gives
    /// all zeros instead of dividing by zero.
    public func unpremultiplied() -> RGBA {
        guard a != 0 else { return .clear }
        return RGBA(r: r / a, g: g / a, b: b / a, a: a)
    }
}

/// A width x height RGBA image, Float32 per component, linear light,
/// premultiplied alpha. A value type: copies are independent.
public struct PixelBuffer: Equatable, Sendable {
    /// The largest pixel count a buffer may hold: 256 megapixels.
    public static let maxPixels = 256 * 1024 * 1024

    /// Components per pixel (R, G, B, A).
    static let channels = 4

    public let width: Int
    public let height: Int
    /// Row-major, `channels` Floats per pixel, top row first.
    private var storage: [Float]

    /// Checks a size and returns its pixel count. Throws `RasterError.invalid`
    /// for a width or height under 1, a pixel count over `maxPixels`, or a size
    /// whose element count would overflow Int. Call it before allocating
    /// anything sized from untrusted width and height.
    public static func validatedSize(width: Int, height: Int) throws -> Int {
        guard width >= 1, height >= 1 else {
            throw RasterError.invalid("size \(width)x\(height): width and height must be at least 1")
        }
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (_, elementOverflow) = pixels.multipliedReportingOverflow(by: channels)
        guard !pixelOverflow, !elementOverflow, pixels <= maxPixels else {
            throw RasterError.invalid("size \(width)x\(height): more than \(maxPixels) pixels")
        }
        return pixels
    }

    /// A buffer of the given size with every pixel set to `fill` (premultiplied).
    /// Throws for an invalid size (see `validatedSize`) or a non-finite fill.
    public init(width: Int, height: Int, fill: RGBA = .clear) throws {
        let pixels = try Self.validatedSize(width: width, height: height)
        guard fill.isFinite else {
            throw RasterError.invalid("fill \(fill): components must be finite")
        }
        self.width = width
        self.height = height
        var storage = [Float](repeating: fill.r, count: pixels * Self.channels)
        for i in stride(from: 0, to: storage.count, by: Self.channels) {
            storage[i + 1] = fill.g
            storage[i + 2] = fill.b
            storage[i + 3] = fill.a
        }
        self.storage = storage
    }

    /// Wraps storage the caller has already sized and checked: `width x height`
    /// passed `validatedSize`, `storage.count == width * height * channels`, and
    /// every component is finite. For this module's image operations only.
    init(checkedWidth width: Int, height: Int, storage: [Float]) {
        self.width = width
        self.height = height
        self.storage = storage
    }

    /// Row-major premultiplied components, for this module's image operations.
    var components: [Float] { storage }

    /// Copies all of `source` into this buffer with its top left at (`x`, `y`),
    /// whole rows at a time. For this module's image operations: the caller
    /// has checked that the rectangle lies inside this buffer. `source` is a
    /// valid buffer, so every copied component is finite.
    mutating func copyRows(from source: PixelBuffer, toX x: Int, toY y: Int) {
        let rowCount = source.width * Self.channels
        for row in 0..<source.height {
            let from = row * rowCount
            let to = ((y + row) * width + x) * Self.channels
            storage.replaceSubrange(to..<(to + rowCount), with: source.storage[from..<(from + rowCount)])
        }
    }

    /// Hands `body` the components of `count` pixels of row `y` from column
    /// `x`, indexed from 0, to read and rewrite in place in one exclusive
    /// access to storage. Storage is copied first only when another value
    /// shares it (as for any write); when this buffer is the only owner,
    /// nothing is copied. For this module's image operations, with
    /// `copyRows`' contract: the caller has checked that the span lies inside
    /// this buffer, writes only finite values, and does not keep the pointer.
    mutating func updateRow<R>(x: Int, y: Int, count: Int,
                               _ body: (UnsafeMutableBufferPointer<Float>) throws -> R) rethrows -> R {
        let start = (y * width + x) * Self.channels
        return try storage.withUnsafeMutableBufferPointer { all in
            try body(UnsafeMutableBufferPointer(rebasing: all[start..<(start + count * Self.channels)]))
        }
    }

    /// The premultiplied pixel at column `x`, row `y` (0, 0 is top left).
    /// Throws `RasterError.invalid` when the coordinate is outside the buffer.
    public func pixel(x: Int, y: Int) throws -> RGBA {
        let i = try index(x: x, y: y)
        return RGBA(r: storage[i], g: storage[i + 1], b: storage[i + 2], a: storage[i + 3])
    }

    /// Stores a premultiplied pixel at column `x`, row `y`. Throws
    /// `RasterError.invalid` when the coordinate is outside the buffer or a
    /// component is NaN or infinite; the buffer is unchanged when it throws.
    public mutating func setPixel(x: Int, y: Int, _ value: RGBA) throws {
        let i = try index(x: x, y: y)
        guard value.isFinite else {
            throw RasterError.invalid("pixel \(value) at (\(x), \(y)): components must be finite")
        }
        storage[i] = value.r
        storage[i + 1] = value.g
        storage[i + 2] = value.b
        storage[i + 3] = value.a
    }

    /// The storage offset of a pixel's first component, bounds-checked.
    /// No overflow: the coordinate is in range and the size was validated.
    private func index(x: Int, y: Int) throws -> Int {
        guard (0..<width).contains(x), (0..<height).contains(y) else {
            throw RasterError.invalid("pixel (\(x), \(y)) is outside \(width)x\(height)")
        }
        return (y * width + x) * Self.channels
    }
}
