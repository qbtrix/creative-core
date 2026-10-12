// Mask.swift: selection masks. A width x height grid of Float coverage values,
// 0 (outside) to 1 (inside). Shapes rasterize with 4x4 supersampling per pixel;
// masks combine with add, subtract, intersect and invert.
// Invariants a reader must keep: the size passed `PixelBuffer.validatedSize`,
// `storage.count == width * height`, and every value is finite and in 0...1.

/// A single-channel coverage buffer, 0...1 per pixel. A value type.
public struct Mask: Equatable, Sendable {
    /// A point in pixel space: (0, 0) is the top-left corner of the top-left
    /// pixel, so pixel (x, y) spans x...x+1 and y...y+1.
    public struct Point: Equatable, Hashable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Samples per pixel along each axis when rasterizing.
    static let samplesPerAxis = 4

    public let width: Int
    public let height: Int
    /// Row-major coverage, one Float per pixel, top row first.
    private var storage: [Float]

    /// A mask of the given size with every pixel set to `fill`. Throws
    /// `RasterError.invalid` for a size `PixelBuffer` rejects or a fill
    /// outside 0...1.
    public init(width: Int, height: Int, fill: Float = 0) throws {
        let pixels = try PixelBuffer.validatedSize(width: width, height: height)
        guard (0...1).contains(fill) else {
            throw RasterError.invalid("mask fill \(fill): must be in 0...1")
        }
        self.width = width
        self.height = height
        storage = [Float](repeating: fill, count: pixels)
    }

    /// The coverage of pixel (x, y). Throws when it is outside the mask.
    public func coverage(x: Int, y: Int) throws -> Float {
        guard (0..<width).contains(x), (0..<height).contains(y) else {
            throw RasterError.invalid("pixel (\(x), \(y)) is outside \(width)x\(height)")
        }
        return storage[y * width + x]
    }

    /// The sum of every pixel's coverage: the covered area in pixels.
    public var area: Double {
        storage.reduce(0) { $0 + Double($1) }
    }

    // MARK: Shapes

    /// A mask with the axis-aligned rectangle at (x, y), `w` x `h` pixels,
    /// covered. Throws for a non-finite value or a negative size.
    public static func rectangle(width: Int, height: Int,
                                 x: Double, y: Double, w: Double, h: Double) throws -> Mask {
        try checkFinite([x, y, w, h])
        guard w >= 0, h >= 0 else {
            throw RasterError.invalid("rectangle size \(w)x\(h): must not be negative")
        }
        return try rasterized(width: width, height: height,
                              minX: x, minY: y, maxX: x + w, maxY: y + h) { sx, sy in
            sx >= x && sx < x + w && sy >= y && sy < y + h
        }
    }

    /// A mask with the ellipse centered at (`centerX`, `centerY`) covered.
    /// Throws for a non-finite value or a negative radius.
    public static func ellipse(width: Int, height: Int, centerX: Double, centerY: Double,
                               radiusX: Double, radiusY: Double) throws -> Mask {
        try checkFinite([centerX, centerY, radiusX, radiusY])
        guard radiusX >= 0, radiusY >= 0 else {
            throw RasterError.invalid("ellipse radii \(radiusX), \(radiusY): must not be negative")
        }
        return try rasterized(width: width, height: height,
                              minX: centerX - radiusX, minY: centerY - radiusY,
                              maxX: centerX + radiusX, maxY: centerY + radiusY) { sx, sy in
            guard radiusX > 0, radiusY > 0 else { return false }
            let dx = (sx - centerX) / radiusX
            let dy = (sy - centerY) / radiusY
            return dx * dx + dy * dy <= 1
        }
    }

    /// A mask with the polygon through `points` covered by the even-odd rule.
    /// The polygon closes itself. Throws for a non-finite point; fewer than
    /// three points cover nothing.
    public static func polygon(width: Int, height: Int, points: [Point]) throws -> Mask {
        try checkFinite(points.flatMap { [$0.x, $0.y] })
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard points.count >= 3, let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            return try Mask(width: width, height: height)
        }
        let edges = zip(points, points.dropFirst() + points.prefix(1))
        return try rasterized(width: width, height: height,
                              minX: minX, minY: minY, maxX: maxX, maxY: maxY) { sx, sy in
            var inside = false
            for (a, b) in edges where (a.y > sy) != (b.y > sy) {
                let crossX = a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x)
                if sx < crossX { inside.toggle() }
            }
            return inside
        }
    }

    /// Throws `RasterError.invalid` if any value is NaN or infinite.
    private static func checkFinite(_ values: [Double]) throws {
        guard values.allSatisfy(\.isFinite) else {
            throw RasterError.invalid("shape coordinates \(values): must be finite")
        }
    }

    /// A mask whose pixels inside the bounds get the fraction of their 4x4
    /// samples for which `inside` is true. Pixels outside the bounds stay 0.
    private static func rasterized(width: Int, height: Int,
                                   minX: Double, minY: Double, maxX: Double, maxY: Double,
                                   inside: (Double, Double) -> Bool) throws -> Mask {
        var mask = try Mask(width: width, height: height)
        // Clamp in Double before converting, so huge bounds can't overflow Int.
        func pixelRange(_ lo: Double, _ hi: Double, _ size: Int) -> Range<Int> {
            let start = Int(min(max(lo.rounded(.down), 0), Double(size)))
            let end = Int(min(max(hi.rounded(.up), 0), Double(size)))
            return start..<max(start, end)
        }
        let n = samplesPerAxis
        let step = 1 / Double(n)
        for py in pixelRange(minY, maxY, height) {
            for px in pixelRange(minX, maxX, width) {
                var hits = 0
                for j in 0..<n {
                    let sy = Double(py) + (Double(j) + 0.5) * step
                    for i in 0..<n where inside(Double(px) + (Double(i) + 0.5) * step, sy) {
                        hits += 1
                    }
                }
                mask.storage[py * width + px] = Float(hits) / Float(n * n)
            }
        }
        return mask
    }

    // MARK: Combining

    /// Adds `other`'s coverage, clamped to 1. Throws if the sizes differ.
    public mutating func add(_ other: Mask) throws {
        try combine(other) { $0 + $1 }
    }

    /// Removes `other`'s coverage, clamped to 0. Throws if the sizes differ.
    public mutating func subtract(_ other: Mask) throws {
        try combine(other) { $0 - $1 }
    }

    /// Keeps only coverage shared with `other` (the product). Throws if the
    /// sizes differ.
    public mutating func intersect(_ other: Mask) throws {
        try combine(other) { $0 * $1 }
    }

    /// Swaps inside and outside: every value becomes 1 minus itself.
    public mutating func invert() {
        for i in storage.indices { storage[i] = 1 - storage[i] }
    }

    /// Applies `op` pixel by pixel and clamps the result to 0...1.
    private mutating func combine(_ other: Mask, _ op: (Float, Float) -> Float) throws {
        guard other.width == width, other.height == height else {
            throw RasterError.invalid("mask sizes \(width)x\(height) and \(other.width)x\(other.height) differ")
        }
        for i in storage.indices {
            storage[i] = min(max(op(storage[i], other.storage[i]), 0), 1)
        }
    }
}
