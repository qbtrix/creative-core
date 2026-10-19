// ToneFixtures.swift: the shared inputs of the tone-pack checks (TP-2 of
// docs/blueprints/core/features/tone-pack.md). Reference colours with
// hand-computed values, `.cube` texts built in code (an identity 17³, a warm
// look 33³ and six damaged files), and a seeded "cast photo". The `.cube`
// texts are generated, not checked in: a 33³ table is about 36,000 lines, and
// test resources would need a Package.swift edit. Everything here is
// deterministic: the same call gives the same value on every platform.
// Parsing is checked in ColorLUTTests (TP-5); this file only builds inputs.
import CoreRaster
import Testing

enum ToneFixtures {
    // MARK: Reference colours

    /// One reference colour: straight, sRGB-encoded `rgb`, and the values
    /// computed by hand from it. `hue` in degrees, `saturation` and
    /// `lightness` are HSL on the encoded values, `luma` is Rec. 709
    /// (0.2126, 0.7152, 0.0722) on the encoded values, `linear` is the sRGB
    /// decode of each channel, `grayDefault` the default black-and-white mix
    /// (40, 60, 40, 60, 20, 80) where the colour sits in one hue range.
    struct Reference {
        let name: String
        let rgb: SIMD3<Float>
        let hue, saturation, lightness, luma: Float
        let linear: SIMD3<Float>
        let grayDefault: Float?

        /// The colour as an opaque buffer pixel: linear, premultiplied.
        var pixel: RGBA { RGBA(r: linear.x, g: linear.y, b: linear.z, a: 1) }
    }

    static let pureRed = Reference(name: "pure red", rgb: [1, 0, 0], hue: 0, saturation: 1, lightness: 0.5,
                                   luma: 0.2126, linear: [1, 0, 0], grayDefault: 0.40)
    static let pureBlue = Reference(name: "pure blue", rgb: [0, 0, 1], hue: 240, saturation: 1, lightness: 0.5,
                                    luma: 0.0722, linear: [0, 0, 1], grayDefault: 0.20)
    /// Hue 0 and lightness 0.5 like `saturated90`, so only saturation differs.
    static let saturated10 = Reference(name: "10% saturated", rgb: [0.55, 0.45, 0.45], hue: 0, saturation: 0.1,
                                       lightness: 0.5, luma: 0.47126,
                                       linear: [0.2632734, 0.1706449, 0.1706449], grayDefault: nil)
    static let saturated90 = Reference(name: "90% saturated", rgb: [0.95, 0.05, 0.05], hue: 0, saturation: 0.9,
                                       lightness: 0.5, luma: 0.24134,
                                       linear: [0.8900054, 0.0039359, 0.0039359], grayDefault: nil)
    /// Hue 20°, inside vibrance's skin range (15°–50°).
    static let skinTone = Reference(name: "skin tone", rgb: [0.8, 0.6, 0.5], hue: 20, saturation: 0.428571,
                                    lightness: 0.65, luma: 0.6353,
                                    linear: [0.6038273, 0.3185468, 0.2140411], grayDefault: nil)
    static let midGrey = Reference(name: "mid grey", rgb: [0.5, 0.5, 0.5], hue: 0, saturation: 0, lightness: 0.5,
                                   luma: 0.5, linear: [0.2140411, 0.2140411, 0.2140411], grayDefault: nil)

    static let references = [pureRed, pureBlue, saturated10, saturated90, skinTone, midGrey]

    // MARK: .cube texts

    /// Header lines every generated `.cube` text has before its table.
    static let headerLines = 5

    /// A `.cube` 1.0 text: a comment, TITLE, LUT_3D_SIZE, DOMAIN_MIN and
    /// DOMAIN_MAX, then one line per entry of `table`, red index fastest.
    /// `entry` gets the (r, g, b) lattice indices.
    static func cube(title: String, size: Int, domainMax: String = "1.0 1.0 1.0", entries: Int? = nil,
                     entry: (Int, Int, Int) -> String) -> String {
        var lines = ["# tone-pack fixture", "TITLE \"\(title)\"", "LUT_3D_SIZE \(size)",
                     "DOMAIN_MIN 0.0 0.0 0.0", "DOMAIN_MAX \(domainMax)"]
        let count = entries ?? size * size * size
        lines.reserveCapacity(headerLines + count)
        for i in 0..<count {
            lines.append(entry(i % size, (i / size) % size, i / (size * size) % size))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The lattice coordinate of index `i` on an axis of `size` samples.
    static func coordinate(_ i: Int, size: Int) -> Float { Float(i) / Float(size - 1) }

    static func line(_ v: SIMD3<Float>) -> String { "\(v.x) \(v.y) \(v.z)" }

    /// Identity entries on a lattice of `size`.
    static func identityEntry(size: Int) -> (Int, Int, Int) -> String {
        { r, g, b in line([coordinate(r, size: size), coordinate(g, size: size), coordinate(b, size: size)]) }
    }

    /// The identity 17³: every entry is its own lattice coordinate.
    static let identity17 = cube(title: "identity 17", size: 17, entry: identityEntry(size: 17))

    /// The warm look, on sRGB-encoded values: red lifted, green a touch,
    /// blue lowered. Affine per channel, so trilinear interpolation between
    /// lattice points reproduces it exactly (up to Float rounding) at any
    /// point, midpoints included; it maps 0...1 into 0...1, no clamping.
    static func warm(_ v: SIMD3<Float>) -> SIMD3<Float> {
        [0.08 + 0.92 * v.x, 0.03 + 0.95 * v.y, 0.9 * v.z]
    }

    /// The warm look's table entry at lattice indices (r, g, b) of a 33³.
    static func warmLattice(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> {
        warm([coordinate(r, size: 33), coordinate(g, size: 33), coordinate(b, size: 33)])
    }

    /// The warm look 33³. Each entry prints the Float `warmLattice` gives in
    /// its shortest round-trip form, so a parser reads back the same Float.
    static let warm33 = cube(title: "warm look 33", size: 33) { line(warmLattice($0, $1, $2)) }

    /// A damaged `.cube` text and why a parser must refuse it.
    struct Damaged {
        let label: String
        let text: String
        /// Lines the text has, so a test can tell a truncated fixture apart.
        let lineCount: Int
    }

    /// Six damaged files: each breaks exactly one rule of the format.
    static let damaged: [Damaged] = {
        let identity2 = identityEntry(size: 2)
        return [
            Damaged(label: "LUT_3D_SIZE 1", text: cube(title: "size 1", size: 1) { _, _, _ in "0.0 0.0 0.0" },
                    lineCount: headerLines + 1),
            Damaged(label: "LUT_3D_SIZE 66", text: cube(title: "size 66", size: 66, entry: identityEntry(size: 66)),
                    lineCount: headerLines + 66 * 66 * 66),
            Damaged(label: "short table", text: cube(title: "short", size: 2, entries: 7, entry: identity2),
                    lineCount: headerLines + 7),
            Damaged(label: "long table", text: cube(title: "long", size: 2, entries: 9, entry: identity2),
                    lineCount: headerLines + 9),
            Damaged(label: "NaN entry", text: cube(title: "nan", size: 2) { r, g, b in
                r == 1 && g == 0 && b == 1 ? "1.0 nan 1.0" : identity2(r, g, b)
            }, lineCount: headerLines + 8),
            Damaged(label: "DOMAIN_MAX 2", text: cube(title: "domain 2", size: 2, domainMax: "2.0 2.0 2.0") { r, g, b in
                line([Float(2 * r), Float(2 * g), Float(2 * b)])
            }, lineCount: headerLines + 8),
        ]
    }()

    // MARK: Cast photo

    /// A seeded "photo" under a uniform colour cast, with a neutral grey patch.
    struct CastPhoto {
        /// Linear, premultiplied, opaque.
        let buffer: PixelBuffer
        /// The patch's top-left corner and size, in pixels.
        let patch: (x: Int, y: Int, width: Int, height: Int)
        /// The linear per-channel gain the cast applies (warm: red up, blue down).
        let cast: SIMD3<Float>
        /// The patch's linear grey before the cast.
        let patchGrey: Float
    }

    /// The cast photo at `width` × `height` (at least 8 × 8). The scene is a
    /// left-to-right grey ramp from 0.05 to 0.9 with ±0.03 seeded noise and
    /// ±0.02 seeded chroma, then every pixel times `cast`, so no channel
    /// clips. The patch, a quarter of each side at the centre, is `patchGrey`
    /// times `cast`.
    static func castPhoto(width: Int = 96, height: Int = 64, seed: UInt64 = 0x70E) throws -> CastPhoto {
        let cast: SIMD3<Float> = [1.08, 1.0, 0.85]
        let grey: Float = 0.5
        let patch = (x: width * 3 / 8, y: height * 3 / 8, width: max(1, width / 4), height: max(1, height / 4))
        var rng = SplitMix64(seed: seed)
        var buffer = try PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let inPatch = (patch.x..<patch.x + patch.width).contains(x)
                    && (patch.y..<patch.y + patch.height).contains(y)
                let level = 0.05 + 0.85 * Float(x) / Float(width - 1) + Float.random(in: -0.03...0.03, using: &rng)
                let chroma = SIMD3<Float>(.random(in: -0.02...0.02, using: &rng), 0, .random(in: -0.02...0.02, using: &rng))
                let base = inPatch ? SIMD3<Float>(repeating: grey) : (SIMD3(repeating: level) + chroma)
                let c = (base * cast).clamped(lowerBound: .zero, upperBound: .one)
                try buffer.setPixel(x: x, y: y, RGBA(r: c.x, g: c.y, b: c.z, a: 1))
            }
        }
        return CastPhoto(buffer: buffer, patch: patch, cast: cast, patchGrey: grey)
    }
}

private func lineCount(_ text: String) -> Int {
    text.split(separator: "\n", omittingEmptySubsequences: false).count - 1
}

@Test func toneFixturesAreDeterministic() throws {
    #expect(ToneFixtures.identity17 == ToneFixtures.identity17)
    #expect(ToneFixtures.warm33 == ToneFixtures.warm33)
    #expect(ToneFixtures.damaged.map(\.text) == ToneFixtures.damaged.map(\.text))
    let a = try ToneFixtures.castPhoto(), b = try ToneFixtures.castPhoto()
    #expect(a.buffer == b.buffer)
    #expect(a.buffer != (try ToneFixtures.castPhoto(seed: 1)).buffer)
    let p = a.patch
    #expect(try a.buffer.pixel(x: p.x, y: p.y) == RGBA(r: 0.54, g: 0.5, b: 0.425, a: 1))
}

@Test func toneFixtureTextsHaveTheirLineCounts() {
    #expect(lineCount(ToneFixtures.identity17) == 5 + 17 * 17 * 17)
    #expect(lineCount(ToneFixtures.warm33) == 5 + 33 * 33 * 33)
    for d in ToneFixtures.damaged {
        #expect(lineCount(d.text) == d.lineCount, "\(d.label)")
    }
    #expect(ToneFixtures.damaged.map(\.label)
        == ["LUT_3D_SIZE 1", "LUT_3D_SIZE 66", "short table", "long table", "NaN entry", "DOMAIN_MAX 2"])
    #expect(ToneFixtures.identity17.split(separator: "\n")[5] == "0.0 0.0 0.0")
    #expect(ToneFixtures.warm33.split(separator: "\n")[5] == "0.08 0.03 0.0")
}

@Test func referenceLumaMatchesRec709() {
    for c in ToneFixtures.references {
        let luma = 0.2126 * c.rgb.x + 0.7152 * c.rgb.y + 0.0722 * c.rgb.z
        #expect(abs(luma - c.luma) <= 1e-6, "\(c.name)")
    }
}
