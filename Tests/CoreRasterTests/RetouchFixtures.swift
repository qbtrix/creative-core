// RetouchFixtures.swift: the images and masks the retouch-heal checks run on
// (packet docs/blueprints/core/features/retouch-heal.md, task RH-2). Built only
// from public CoreRaster API (PixelBuffer, Mask, RGBA) and seeded SplitMix64,
// so every fixture is the same on every platform.
//
// - `spottedPhoto`: a light textured photo with three dark spots; spot 1 has a
//   ring around it (FillFromSurroundingsTests, RetouchWalkTests).
// - `gradientField`: an affine colour field with a known value at every pixel,
//   so a heal that keeps gradients reproduces it exactly (HealTests).
// - `redEdge`: opaque red left of a column, opaque white right of it (SmudgeTests).
// - `roundDab`, `disc`: round masks, hard or feathered (every suite).
// - `tonePatches`: grey patches at luma 0.1, 0.5 and 0.95 plus a tinted one
//   for sponge (ToneDabTests).
import CoreRaster
import Testing

enum RetouchFixtures {
    /// One dark spot: its centre and radius in pixels, a hard hole mask that
    /// covers it with a pixel to spare, and a ring of texture around the hole.
    struct Spot {
        let centerX: Double
        let centerY: Double
        let radius: Double
        let hole: Mask
        let ring: Mask
    }

    /// The textured photo before and after its spots were painted in.
    struct SpottedPhoto {
        let clean: PixelBuffer
        let spotted: PixelBuffer
        let spots: [Spot]
    }

    /// The colour every spot is painted with, opaque and dark.
    static let spotColor = RGBA(r: 0.05, g: 0.04, b: 0.04, a: 1)

    /// Grey levels of the tone patches, in patch order.
    static let lumaLevels: [Float] = [0.1, 0.5, 0.95]

    /// The tinted fourth tone patch, for sponge: a muted opaque orange.
    static let tint = RGBA(r: 0.6, g: 0.4, b: 0.25, a: 1)

    /// The light gradient under the texture at (x, y): 0.55 at the left
    /// edge rising to 0.8 at the right, with a slight warm tint.
    static func lightGradient(x: Int, y: Int, width: Int, height: Int) -> RGBA {
        let t = Float(x) / Float(max(width - 1, 1))
        let s = Float(y) / Float(max(height - 1, 1))
        let base = 0.55 + 0.25 * t + 0.05 * s
        return RGBA(r: base + 0.03, g: base, b: base - 0.03, a: 1)
    }

    /// A light textured photo (the gradient plus seeded noise of ±0.08 per
    /// pixel) with three dark spots on its middle row, at a quarter, half and
    /// three quarters of its width, each of radius `min(width, height) / 16`.
    /// Spot 1's ring runs from the hole's edge out to twice the spot radius.
    static func spottedPhoto(width: Int, height: Int, seed: UInt64) throws -> SpottedPhoto {
        var rng = SplitMix64(seed: seed)
        var clean = try PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                var p = lightGradient(x: x, y: y, width: width, height: height)
                let grain = Float.random(in: -0.08...0.08, using: &rng)
                let tint = Float.random(in: -0.01...0.01, using: &rng)
                p.r += grain + tint
                p.g += grain
                p.b += grain - tint
                try clean.setPixel(x: x, y: y, p)
            }
        }
        let radius = max(2, Double(min(width, height)) / 16)
        var spotted = clean
        var spots: [Spot] = []
        for fraction in [0.25, 0.5, 0.75] {
            let cx = Double(width) * fraction, cy = Double(height) / 2
            let paint = try disc(width: width, height: height, centerX: cx, centerY: cy, radius: radius)
            for y in 0..<height {
                for x in 0..<width {
                    let c = try paint.coverage(x: x, y: y)
                    guard c > 0 else { continue }
                    try spotted.setPixel(x: x, y: y, mix(try spotted.pixel(x: x, y: y), spotColor, c))
                }
            }
            let hole = try disc(width: width, height: height, centerX: cx, centerY: cy, radius: radius + 1)
            var ring = try disc(width: width, height: height, centerX: cx, centerY: cy, radius: 2 * radius)
            try ring.subtract(hole)
            spots.append(Spot(centerX: cx, centerY: cy, radius: radius, hole: hole, ring: ring))
        }
        return SpottedPhoto(clean: clean, spotted: spotted, spots: spots)
    }

    /// The known smooth field at (x, y): every channel affine in x and y, so
    /// its Laplacian is zero and a gradient-domain heal reproduces it.
    static func fieldValue(x: Int, y: Int) -> RGBA {
        let fx = Float(x), fy = Float(y)
        return RGBA(r: 0.2 + 0.004 * fx, g: 0.3 + 0.003 * fy, b: 0.25 + 0.002 * (fx + fy), a: 1)
    }

    /// A buffer holding `fieldValue` at every pixel. Keep width and height at
    /// most 150 so every channel stays in 0...1.
    static func gradientField(width: Int, height: Int) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                try buffer.setPixel(x: x, y: y, fieldValue(x: x, y: y))
            }
        }
        return buffer
    }

    /// Opaque red in columns below `edgeX`, opaque white from `edgeX` on.
    static func redEdge(width: Int, height: Int, edgeX: Int) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: width, height: height, fill: RGBA(r: 1, g: 1, b: 1, a: 1))
        for y in 0..<height {
            for x in 0..<min(edgeX, width) {
                try buffer.setPixel(x: x, y: y, RGBA(r: 1, g: 0, b: 0, a: 1))
            }
        }
        return buffer
    }

    /// A round mask centred at (`centerX`, `centerY`). Hardness 1 is a hard
    /// disc; below 1, coverage is 1 out to `radius × hardness` and falls in
    /// eight even steps to 0 at `radius`.
    static func disc(width: Int, height: Int, centerX: Double, centerY: Double,
                     radius: Double, hardness: Double = 1) throws -> Mask {
        guard hardness < 1 else {
            return try Mask.ellipse(width: width, height: height, centerX: centerX, centerY: centerY,
                                    radiusX: radius, radiusY: radius)
        }
        let steps = 8
        var mask = try Mask(width: width, height: height)
        for k in 1...steps {
            let r = radius * (hardness + (1 - hardness) * Double(k) / Double(steps))
            var band = try Mask.ellipse(width: width, height: height, centerX: centerX, centerY: centerY,
                                        radiusX: r, radiusY: r)
            try band.intersect(Mask(width: width, height: height, fill: 1 / Float(steps)))
            try mask.add(band)
        }
        return mask
    }

    /// A round dab of `radius` pixels on its own square mask, `2 × radius`
    /// pixels a side with the centre at (radius, radius): hard by default,
    /// feathered for a hardness below 1.
    static func roundDab(radius: Int, hardness: Double = 1) throws -> Mask {
        try disc(width: 2 * radius, height: 2 * radius, centerX: Double(radius), centerY: Double(radius),
                 radius: Double(radius), hardness: hardness)
    }

    /// Four `side` × `side` opaque patches in a row: greys at each of
    /// `lumaLevels`, then `tint`.
    static func tonePatches(side: Int) throws -> PixelBuffer {
        let colors = lumaLevels.map { RGBA(r: $0, g: $0, b: $0, a: 1) } + [tint]
        var buffer = try PixelBuffer(width: side * colors.count, height: side)
        for (i, color) in colors.enumerated() {
            for y in 0..<side {
                for x in (i * side)..<((i + 1) * side) {
                    try buffer.setPixel(x: x, y: y, color)
                }
            }
        }
        return buffer
    }

    /// `a` blended toward `b` by `t`; `t == 1` gives exactly `b`.
    static func mix(_ a: RGBA, _ b: RGBA, _ t: Float) -> RGBA {
        let u = 1 - t
        return RGBA(r: a.r * u + b.r * t, g: a.g * u + b.g * t, b: a.b * u + b.b * t, a: a.a * u + b.a * t)
    }
}

@Test func retouchFixturesBuild() throws {
    let photo = try RetouchFixtures.spottedPhoto(width: 160, height: 96, seed: 7)
    #expect(photo.spotted.width == 160 && photo.spotted.height == 96 && photo.spots.count == 3)
    let spot1 = try #require(photo.spots.first)
    #expect(spot1.radius == 6 && spot1.centerX == 40 && spot1.centerY == 48)
    #expect(try photo.spotted.pixel(x: 40, y: 48) == RetouchFixtures.spotColor)
    #expect(try photo.spotted.pixel(x: 0, y: 0) == photo.clean.pixel(x: 0, y: 0))
    #expect(try photo.clean.pixel(x: 40, y: 48) != photo.clean.pixel(x: 41, y: 48))
    #expect(try spot1.hole.coverage(x: 40, y: 48) == 1 && spot1.ring.coverage(x: 40, y: 48) == 0)
    #expect(try spot1.ring.coverage(x: 50, y: 48) == 1 && spot1.hole.coverage(x: 50, y: 48) == 0)
    #expect(try RetouchFixtures.spottedPhoto(width: 160, height: 96, seed: 7).spotted == photo.spotted)
    #expect(try RetouchFixtures.spottedPhoto(width: 160, height: 96, seed: 8).spotted != photo.spotted)

    let field = try RetouchFixtures.gradientField(width: 64, height: 48)
    #expect(field.width == 64 && field.height == 48)
    #expect(try field.pixel(x: 10, y: 20) == RGBA(r: 0.2 + 0.004 * 10, g: 0.3 + 0.003 * 20,
                                                  b: 0.25 + 0.002 * 30, a: 1))

    let edge = try RetouchFixtures.redEdge(width: 40, height: 10, edgeX: 20)
    #expect(try edge.pixel(x: 19, y: 5) == RGBA(r: 1, g: 0, b: 0, a: 1))
    #expect(try edge.pixel(x: 20, y: 5) == RGBA(r: 1, g: 1, b: 1, a: 1))

    let hard = try RetouchFixtures.roundDab(radius: 10)
    #expect(hard.width == 20 && hard.height == 20)
    #expect(try hard.coverage(x: 10, y: 10) == 1 && hard.coverage(x: 0, y: 0) == 0)
    let soft = try RetouchFixtures.roundDab(radius: 10, hardness: 0.5)
    #expect(try soft.coverage(x: 10, y: 10) == 1 && soft.coverage(x: 0, y: 0) == 0)
    let feather = try soft.coverage(x: 17, y: 10)
    #expect(try feather > 0 && feather < 1 && feather < hard.coverage(x: 17, y: 10))
    #expect(soft.area < hard.area)

    let patches = try RetouchFixtures.tonePatches(side: 8)
    #expect(patches.width == 32 && patches.height == 8)
    #expect(try patches.pixel(x: 3, y: 3) == RGBA(r: 0.1, g: 0.1, b: 0.1, a: 1))
    #expect(try patches.pixel(x: 12, y: 3) == RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1))
    #expect(try patches.pixel(x: 20, y: 3) == RGBA(r: 0.95, g: 0.95, b: 0.95, a: 1))
    #expect(try patches.pixel(x: 28, y: 3) == RetouchFixtures.tint)
}
