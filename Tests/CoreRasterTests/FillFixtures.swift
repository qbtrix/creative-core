// FillFixtures.swift: images and expected values for the fill-tools checks
// (FloodFillTests, ColorRangeTests, RasterGradientTests, FillWalkTests,
// FillBudgetTests). Everything is a fixed formula or seeded SplitMix64, so a
// fixture is the same on every run and platform. The 100 MP buffer is a
// builder, never a stored value: only the test that calls it allocates it.
import CoreRaster
import Testing
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// An integer pixel rectangle: columns `x..<x + width`, rows `y..<y + height`.
struct FillRect: Hashable {
    var x: Int, y: Int, width: Int, height: Int

    func contains(x px: Int, y py: Int) -> Bool {
        (x..<(x + width)).contains(px) && (y..<(y + height)).contains(py)
    }

    /// The one-pixel ring just outside this rectangle.
    func ringContains(x px: Int, y py: Int) -> Bool {
        let outer = FillRect(x: x - 1, y: y - 1, width: width + 2, height: height + 2)
        return outer.contains(x: px, y: py) && !contains(x: px, y: py)
    }
}

/// A scene of flat opaque regions on background colour A.
/// - `regionB` and `twinB` are colour B, apart, each with a one-pixel
///   anti-aliased ring of `border(B)` (A and B mixed, 0.15 from B).
/// - `regionC` is colour C with the same kind of ring, for colour range.
/// - `diagonalPair` are two squares of colour D that touch only at a
///   corner: 8-connected joins them, 4-connected does not.
struct FillScene {
    static let colorA = RGBA(r: 0.9, g: 0.9, b: 0.9, a: 1)
    static let colorB = RGBA(r: 0.1, g: 0.3, b: 0.8, a: 1)
    static let colorC = RGBA(r: 0.8, g: 0.2, b: 0.1, a: 1)
    static let colorD = RGBA(r: 0.1, g: 0.6, b: 0.2, a: 1)

    /// A's share of the ring colour: 0.355 puts B's ring 0.15 from B in
    /// OKLab, so a fill from B at tolerance 0.1 half-covers it
    /// (`1 - (0.15 - 0.1) / 0.1`). C's ring sits about 0.137 from C.
    static let borderShareOfA: Float = 0.355

    /// The anti-aliased ring colour around a region of `color` on A.
    static func border(_ color: RGBA) -> RGBA {
        let s = borderShareOfA
        return RGBA(r: color.r + (colorA.r - color.r) * s, g: color.g + (colorA.g - color.g) * s,
                    b: color.b + (colorA.b - color.b) * s, a: 1)
    }

    let buffer: PixelBuffer
    let regionB: FillRect
    let twinB: FillRect
    let regionC: FillRect
    let diagonalPair: (FillRect, FillRect)

    /// A seed pixel inside B, inside C and in the background.
    var seedB: (x: Int, y: Int) { (regionB.x + regionB.width / 2, regionB.y + regionB.height / 2) }
    var seedC: (x: Int, y: Int) { (regionC.x + regionC.width / 2, regionC.y + regionC.height / 2) }
    var seedA: (x: Int, y: Int) { (0, 0) }

    /// Lays the regions out in proportion to the size: 64 x 48 for unit
    /// checks, 2000 x 1500 for the KJ-FT walk. Needs at least 32 x 24.
    init(width: Int = 64, height: Int = 48) throws {
        guard width >= 32, height >= 24 else { throw RasterError.invalid("fill scene needs 32x24") }
        let side = max(2, width / 32)
        regionB = FillRect(x: width / 8, y: height / 6, width: width / 4, height: height / 3)
        twinB = FillRect(x: 5 * width / 8, y: height / 6, width: width / 4, height: height / 3)
        regionC = FillRect(x: width / 8, y: 2 * height / 3, width: width / 4, height: height / 6)
        let d0 = FillRect(x: 5 * width / 8, y: 2 * height / 3, width: side, height: side)
        diagonalPair = (d0, FillRect(x: d0.x + side, y: d0.y + side, width: side, height: side))
        var image = try PixelBuffer(width: width, height: height, fill: Self.colorA)
        for (rect, color) in [(regionB, Self.colorB), (twinB, Self.colorB), (regionC, Self.colorC)] {
            for y in (rect.y - 1)...(rect.y + rect.height) {
                for x in (rect.x - 1)...(rect.x + rect.width) {
                    try image.setPixel(x: x, y: y, rect.contains(x: x, y: y) ? color : Self.border(color))
                }
            }
        }
        for rect in [diagonalPair.0, diagonalPair.1] {
            for y in rect.y..<(rect.y + rect.height) {
                for x in rect.x..<(rect.x + rect.width) { try image.setPixel(x: x, y: y, Self.colorD) }
            }
        }
        buffer = image
    }
}

enum FillFixtures {
    /// The 100 MP worst case for flood fill's memory bound: 10 000 x 10 000.
    static let largeSide = 10_000

    /// One colour everywhere. Called with no size it allocates the 100 MP
    /// buffer (1.6 GB of Float storage), so only the budget test should.
    static func singleColor(_ color: RGBA = FillScene.colorA,
                            width: Int = largeSide, height: Int = largeSide) throws -> PixelBuffer {
        try PixelBuffer(width: width, height: height, fill: color)
    }

    /// A 4 x 1 row: B opaque at x 0 and 1, B straight at alpha 0.8
    /// (premultiplied) at x 2 and 3. The two halves differ only in alpha.
    static func alphaPair() throws -> PixelBuffer {
        var image = try PixelBuffer(width: 4, height: 1)
        let faint = RGBA(r: FillScene.colorB.r, g: FillScene.colorB.g, b: FillScene.colorB.b, a: 0.8).premultiplied()
        for x in 0..<4 { try image.setPixel(x: x, y: 0, x < 2 ? FillScene.colorB : faint) }
        return image
    }

    /// Seeded opaque noise with components in 0...1, for `sampledColor`'s box mean.
    static func noise(width: Int = 7, height: Int = 7, seed: UInt64 = 0xF111) throws -> PixelBuffer {
        var rng = SplitMix64(seed: seed)
        var image = try PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                try image.setPixel(x: x, y: y, RGBA(r: .random(in: 0...1, using: &rng),
                                                    g: .random(in: 0...1, using: &rng),
                                                    b: .random(in: 0...1, using: &rng), a: 1))
            }
        }
        return image
    }

    /// The mean of the (2r + 1)^2 box around (x, y), summed in Double.
    static func boxMean(_ image: PixelBuffer, x: Int, y: Int, radius: Int) throws -> RGBA {
        var sum = (r: 0.0, g: 0.0, b: 0.0, a: 0.0)
        for dy in -radius...radius {
            for dx in -radius...radius {
                let p = try image.pixel(x: x + dx, y: y + dy)
                sum = (sum.r + Double(p.r), sum.g + Double(p.g), sum.b + Double(p.b), sum.a + Double(p.a))
            }
        }
        let n = Double((2 * radius + 1) * (2 * radius + 1))
        return RGBA(r: Float(sum.r / n), g: Float(sum.g / n), b: Float(sum.b / n), a: Float(sum.a / n))
    }

    /// The gradient endpoints: pixel centres (10, 10) and (20, 10), 10 px apart along +x.
    static let gradientA = Mask.Point(x: 10.5, y: 10.5)
    static let gradientB = Mask.Point(x: 20.5, y: 10.5)

    /// Hand-computed `t` at five pixel centres per shape, for the endpoints above.
    /// Angle runs from the direction of b, towards +y (clockwise on screen).
    static let gradientCases: [(shape: RasterGradientShape, x: Int, y: Int, t: Double)] = [
        (.linear, 5, 10, 0), (.linear, 10, 10, 0), (.linear, 13, 4, 0.3), (.linear, 15, 17, 0.5), (.linear, 25, 10, 1),
        (.radial, 10, 10, 0), (.radial, 10, 7, 0.3), (.radial, 13, 14, 0.5), (.radial, 16, 18, 1), (.radial, 30, 10, 1),
        (.angle, 15, 10, 0), (.angle, 15, 15, 0.125), (.angle, 10, 15, 0.25), (.angle, 5, 10, 0.5), (.angle, 10, 5, 0.75),
        (.reflected, 10, 10, 0), (.reflected, 5, 10, 0.5), (.reflected, 15, 10, 0.5), (.reflected, 0, 10, 1),
        (.reflected, 27, 3, 1),
        (.diamond, 13, 14, 0.4), (.diamond, 15, 10, 0.5), (.diamond, 10, 15, 0.5), (.diamond, 2, 13, 0.8),
        (.diamond, 30, 10, 1),
    ]

    /// The packet's formula for `t` at point `p`, clamped to 0...1.
    static func analyticT(_ shape: RasterGradientShape, at p: Mask.Point,
                          from a: Mask.Point, to b: Mask.Point) -> Double {
        let (vx, vy) = (b.x - a.x, b.y - a.y), (dx, dy) = (p.x - a.x, p.y - a.y)
        let length2 = vx * vx + vy * vy
        let along = (dx * vx + dy * vy) / length2
        let across = (vx * dy - vy * dx) / length2
        let t: Double
        switch shape {
        case .linear: t = along
        case .radial: t = (dx * dx + dy * dy).squareRoot() / length2.squareRoot()
        case .angle:
            let turn = (atan2(dy, dx) - atan2(vy, vx)) / (2 * Double.pi)
            t = turn - turn.rounded(.down)
        case .reflected: t = abs(along)
        case .diamond: t = max(abs(along), abs(across))
        }
        return min(max(t, 0), 1)
    }
}

@Suite struct FillFixturesTests {
    @Test func sceneBuildsWithItsRegions() throws {
        let scene = try FillScene()
        #expect(scene.buffer.width == 64 && scene.buffer.height == 48)
        let b = scene.regionB, twin = scene.twinB
        #expect(try scene.buffer.pixel(x: scene.seedB.x, y: scene.seedB.y) == FillScene.colorB)
        #expect(try scene.buffer.pixel(x: b.x - 1, y: b.y) == FillScene.border(FillScene.colorB))
        #expect(try scene.buffer.pixel(x: b.x - 2, y: b.y) == FillScene.colorA)
        #expect(try scene.buffer.pixel(x: twin.x, y: twin.y) == FillScene.colorB)
        #expect(b.x + b.width + 1 < twin.x - 1)  // a band of A keeps the twin disconnected
        #expect(try scene.buffer.pixel(x: scene.seedC.x, y: scene.seedC.y) == FillScene.colorC)
        #expect(try scene.buffer.pixel(x: scene.regionC.x, y: scene.regionC.y - 1) == FillScene.border(FillScene.colorC))
        let (d0, d1) = scene.diagonalPair
        #expect(try scene.buffer.pixel(x: d0.x + d0.width - 1, y: d0.y + d0.height - 1) == FillScene.colorD)
        #expect(try scene.buffer.pixel(x: d1.x, y: d1.y) == FillScene.colorD)
        #expect(try scene.buffer.pixel(x: d1.x, y: d1.y - 1) == FillScene.colorA)  // corner only
        #expect(try scene.buffer.pixel(x: d1.x - 1, y: d1.y) == FillScene.colorA)
        let walk = try FillScene(width: 200, height: 150)
        #expect(try walk.buffer.pixel(x: walk.seedB.x, y: walk.seedB.y) == FillScene.colorB)
        #expect(throws: RasterError.self) { try FillScene(width: 31, height: 24) }
    }

    @Test func singleColorAndNoiseBuild() throws {
        #expect(FillFixtures.largeSide * FillFixtures.largeSide == 100_000_000)
        #expect(FillFixtures.largeSide * FillFixtures.largeSide <= PixelBuffer.maxPixels)
        let small = try FillFixtures.singleColor(FillScene.colorC, width: 5, height: 3)
        #expect(small.width == 5 && small.height == 3)
        #expect(try small.pixel(x: 4, y: 2) == FillScene.colorC)
        let noise = try FillFixtures.noise()
        #expect(noise == (try FillFixtures.noise()))
        #expect(try noise.pixel(x: 0, y: 0) != noise.pixel(x: 1, y: 0))
        let mean = try FillFixtures.boxMean(noise, x: 3, y: 3, radius: 0)
        #expect(mean == (try noise.pixel(x: 3, y: 3)))
    }

    @Test func gradientTableMatchesFormula() {
        #expect(FillFixtures.gradientCases.count == 25)
        for c in FillFixtures.gradientCases {
            let p = Mask.Point(x: Double(c.x) + 0.5, y: Double(c.y) + 0.5)
            let t = FillFixtures.analyticT(c.shape, at: p, from: FillFixtures.gradientA, to: FillFixtures.gradientB)
            #expect(abs(t - c.t) < 1e-9, "\(c.shape) at (\(c.x), \(c.y)): \(t), table says \(c.t)")
        }
    }
}
