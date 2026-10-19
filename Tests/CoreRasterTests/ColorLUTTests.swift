// ColorLUTTests.swift: tone-pack TP-5's acceptance for 3D LUTs, written first
// (TP-1 of docs/blueprints/core/features/tone-pack.md): `CubeLUT.parse` and
// `applying(_:)`, on ToneFixtures' `.cube` texts.
import CoreRaster
import Testing

@Suite struct ColorLUTTests {
    @Test func identityWithinTolerance() throws {
        let lut = try CubeLUT.parse(ToneFixtures.identity17)
        #expect(lut.size == 17)
        #expect(try CubeLUT.parse(ToneFixtures.cube(title: "identity 2", size: 2,
                                                     entry: ToneFixtures.identityEntry(size: 2))).size == 2)
        let b = try ToneCheck.seeded(width: 32, height: 16, seed: 0xD1)
        for (p, q) in zip(try ToneCheck.pixels(b), try ToneCheck.pixels(b.applying(lut))) {
            #expect(ToneCheck.gap(p, q) <= 1e-5, "\(p)")
        }
    }

    /// The warm 33³ table holds the hand values at lattice points, red index
    /// fastest, and `applying` gives them back at those 8 lattice inputs.
    @Test func redFastest() throws {
        let lut = try CubeLUT.parse(ToneFixtures.warm33)
        #expect(lut.size == 33)
        let points = [(0, 0, 0), (32, 0, 0), (0, 32, 0), (0, 0, 32), (5, 17, 29), (31, 2, 11), (16, 16, 16), (32, 32, 32)]
        for (r, g, b) in points {
            #expect(lut.table[r + 33 * g + 33 * 33 * b] == ToneFixtures.warmLattice(r, g, b), "\(r), \(g), \(b)")
        }
        let c = { (i: Int) in Double(ToneFixtures.coordinate(i, size: 33)) }
        let row = try ToneCheck.row(points.map { ToneCheck.pixel([c($0.0), c($0.1), c($0.2)]) })
        for ((r, g, b), q) in zip(points, try ToneCheck.pixels(row.applying(lut))) {
            let want = SIMD3<Double>(ToneFixtures.warmLattice(r, g, b))
            #expect(ToneCheck.gap(ToneCheck.encoded(q), want) <= 1e-5, "applied \(r), \(g), \(b)")
        }
    }

    /// Between lattice points the warm look is affine, so trilinear gives it exactly.
    @Test func midpointsTrilinear() throws {
        let lut = try CubeLUT.parse(ToneFixtures.warm33)
        let cells: [SIMD3<Double>] = [[0, 0, 0], [31, 0, 0], [0, 31, 0], [0, 0, 31], [4, 19, 27], [30, 1, 12],
                                      [15, 16, 17], [31, 31, 31]]
        let input = cells.map { ($0 + 0.5) / 32 }
        let out = try ToneCheck.pixels(ToneCheck.row(input.map { ToneCheck.pixel($0) }).applying(lut))
        for (v, q) in zip(input, out) {
            let w = ToneFixtures.warm(SIMD3<Float>(v))
            #expect(ToneCheck.gap(ToneCheck.encoded(q), SIMD3<Double>(w)) <= 1e-6, "\(v)")
        }
    }

    @Test func damagedFilesThrow() {
        for d in ToneFixtures.damaged {
            #expect(throws: RasterError.self, "\(d.label)") { try CubeLUT.parse(d.text) }
        }
    }

    /// A table longer than n³ is refused at its first extra line, and a size
    /// outside 2...65 at its LUT_3D_SIZE line, before ColorLUT sees either.
    @Test func longTableRefusedAtLine() {
        func message(_ label: String) -> String {
            guard let d = ToneFixtures.damaged.first(where: { $0.label == label }) else { return "no fixture" }
            do {
                _ = try CubeLUT.parse(d.text)
                return "parsed"
            } catch let RasterError.invalid(why) {
                return why
            } catch {
                return "\(error)"
            }
        }
        let long = message("long table")
        #expect(long.contains(".cube line \(ToneFixtures.headerLines + 9)") && long.contains("more than 8 entries"), "\(long)")
        for label in ["LUT_3D_SIZE 1", "LUT_3D_SIZE 66"] {
            let why = message(label)
            #expect(why.contains(".cube line 3") && why.contains("LUT_3D_SIZE"), "\(label): \(why)")
        }
    }

    /// Each bad LUT_3D_SIZE line says what it found: the out-of-range value,
    /// a second size line, or the text that is not one integer.
    @Test func sizeErrorNamesValue() {
        func message(_ text: String) -> String {
            do {
                _ = try CubeLUT.parse(text)
                return "parsed"
            } catch let RasterError.invalid(why) {
                return why
            } catch {
                return "\(error)"
            }
        }
        let range = message("LUT_3D_SIZE 66\n")
        #expect(range.contains(".cube line 1") && range.contains("66") && range.contains("2...65"), "\(range)")
        let twice = message("LUT_3D_SIZE 2\nLUT_3D_SIZE 2\n")
        #expect(twice.contains(".cube line 2") && twice.contains("twice"), "\(twice)")
        let float = message("LUT_3D_SIZE 64.0\n")
        #expect(float.contains(".cube line 1") && float.contains("'64.0'"), "\(float)")
        let extra = message("LUT_3D_SIZE 4 4\n")
        #expect(extra.contains("'4 4'"), "\(extra)")
    }

    @Test func refusesOtherDomain() {
        let other = ToneFixtures.damaged.filter { $0.label == "DOMAIN_MAX 2" }
        #expect(other.count == 1)
        for d in other {
            #expect(throws: RasterError.self) { try CubeLUT.parse(d.text) }
        }
    }

    /// 500 seeded mutations of a 3³ identity: each parses to a valid LUT or
    /// throws `RasterError`, never crashes.
    @Test func fuzz() {
        let base = Array(ToneFixtures.cube(title: "fuzz", size: 3, entry: ToneFixtures.identityEntry(size: 3)).utf8)
        let alphabet = Array("0123456789.-+eE nan\n#LUT_3DSIZEDOMAIN_MINMAXTITLE\"".utf8)
        var rng = SplitMix64(seed: 0xD2)
        for round in 0..<500 {
            var bytes = base
            for _ in 0..<Int.random(in: 1...4, using: &rng) where !bytes.isEmpty {
                let i = Int.random(in: 0..<bytes.count, using: &rng)
                switch rng.next() % 4 {
                case 0: bytes[i] = alphabet[Int.random(in: 0..<alphabet.count, using: &rng)]
                case 1: bytes.remove(at: i)
                case 2: bytes.insert(alphabet[Int.random(in: 0..<alphabet.count, using: &rng)], at: i)
                default: bytes.removeSubrange(i...)
                }
            }
            do {
                let lut = try CubeLUT.parse(String(decoding: bytes, as: UTF8.self))
                #expect((2...65).contains(lut.size) && lut.table.count == lut.size * lut.size * lut.size, "round \(round)")
            } catch is RasterError {
            } catch {
                Issue.record("round \(round): \(error)")
            }
        }
    }
}
