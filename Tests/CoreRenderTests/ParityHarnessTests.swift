// ParityHarnessTests.swift: the parity harness (render-backend RB-6).
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreColor
import CoreRaster
import CoreRender
import Testing

/// 3x2 opaque sRGB bytes 5, 150, 200 with pixel (2, 1)'s red `5 + delta`. Red
/// sits on the sRGB toe (one level is 3e-4 linear), so the byte bound decides.
private func compare(_ delta: UInt8, _ tolerance: ParityTolerance) throws -> ParityResult {
    let base = [[UInt8]](repeating: [5, 150, 200, 255], count: 6).flatMap { $0 }
    var other = base
    other[20] += delta
    return try ParityHarness.compare(PixelBuffer(rgba8: base, width: 3, height: 2),
                                     PixelBuffer(rgba8: other, width: 3, height: 2), tolerance: tolerance)
}

private func fill(_ w: Int, _ h: Int, _ r: Float, _ g: Float, _ b: Float, _ a: Float) throws -> PixelBuffer { try PixelBuffer(width: w, height: h, fill: RGBA(r: r, g: g, b: b, a: a)) }

@Suite struct ParityHarnessTests {
    @Test func byteBoundsHoldExactly() throws {
        let same = try compare(0, .standard)
        #expect(same.passed && same.worstByteDelta == 0 && same.worstLinearDelta == 0)
        #expect(try compare(2, .standard).passed && compare(4, .nonSeparable).passed)
        let three = try compare(3, .standard)
        #expect(!three.passed && three.worstByteDelta == 3 && three.worstByteX == 2 && three.worstByteY == 1)
        #expect(three.worstLinearDelta < ParityTolerance.standard.linear, "the byte bound fails it")
        #expect(try !compare(5, .nonSeparable).passed)
        #expect([ParityTolerance.standard, .nonSeparable] == [.init(bytes: 2, linear: 1e-3), .init(bytes: 4, linear: 4e-3)])
    }

    @Test func goldenCompareChecksBytesInTheGoldensSpace() throws {
        let base = [[UInt8]](repeating: [5, 150, 200, 255], count: 6).flatMap { $0 }
        let golden = try ParityGolden(PixelBuffer(rgba8: base, width: 3, height: 2), tolerance: .standard)
        let off = { (delta: UInt8) throws -> ParityResult in
            var other = base
            other[20] += delta
            return try ParityHarness.compare(golden: golden, PixelBuffer(rgba8: other, width: 3, height: 2))
        }
        #expect(try off(0).worstByteDelta == 0 && off(2).passed)
        let three = try off(3)
        #expect(!three.passed && three.worstByteDelta == 3 && three.worstByteX == 2 && three.worstByteY == 1, "\(three)")
        #expect(throws: RenderError.self) { try ParityHarness.compare(golden: golden, fill(2, 3, 0, 0, 0, 1)) }
    }

    @Test func goldenCompareEncodesInTheGoldensSpace() throws {
        let red = try fill(1, 1, 1, 0, 0, 1)
        let golden = try ParityGolden(red, colorSpace: .displayP3, tolerance: .standard)
        #expect(try golden.bytes != red.rgba8(colorSpace: .sRGB), "saturated red differs in P3")
        let result = try ParityHarness.compare(golden: golden, red)
        #expect(result.passed && result.worstByteDelta == 0, "\(result)")
        #expect(!"\(result)".contains("linear"), "a golden compare checks bytes only: \(result)")
    }

    @Test func checkedInBlurGoldensPassWhereTheDecodedLinearCompareFails() throws {
        let cpu = CPUBackend()
        var linearFailures = 0
        for sample in try ParityHarness.sampleSet(for: .blur) {
            let golden = try ParityGolden.band(from: CPUGoldenTests.root, op: .blur, sample: sample.name)
            let result = try ParityHarness.render(sample, on: cpu)
            #expect(try ParityHarness.compare(golden: golden, result).passed, "\(sample.name)")
            if try !ParityHarness.compare(golden.buffer(), result, tolerance: .standard).passed { linearFailures += 1 }
        }
        // Linear 0.998 is display byte 255, which decodes to 1: 2e-3 off, over `.standard.linear`.
        #expect(linearFailures > 0, "a golden's bytes decoded to linear are off by up to half a level")
    }

    @Test func pixelsInvisibleInBothCompareOnlyAlpha() throws {
        let golden = { (bytes: [UInt8]) in
            try ParityGolden(header: Data(#"{"width":1,"height":1,"colorSpace":"sRGB","tolerance":{"bytes":2,"linear":0.001}}"#.utf8),
                             bytes: Data(bytes))
        }
        let clear = try ParityHarness.compare(golden: golden([255, 255, 0, 0]), fill(1, 1, 0, 0, 0, 0))
        #expect(clear.passed && clear.worstByteDelta == 0, "\(clear)")
        let visible = try ParityHarness.compare(golden: golden([255, 255, 0, 1]), fill(1, 1, 0, 0, 0, 1.0 / 255))
        #expect(!visible.passed && visible.worstByteDelta == 255, "\(visible)")
        // Only the golden's alpha byte is 0: the result is visible (alpha byte 1), so its colour counts.
        let oneSide = try ParityHarness.compare(golden: golden([255, 255, 0, 0]), fill(1, 1, 0, 0, 0, 1.0 / 255))
        #expect(!oneSide.passed && oneSide.worstByteDelta == 255, "\(oneSide)")
        // A real band: blur's alpha-subnormal keeps colour under alpha byte 0; flushed to clear, it passes.
        let band = try ParityGolden.band(from: CPUGoldenTests.root, op: .blur, sample: "alpha-subnormal")
        var flushed = band.bytes
        for i in stride(from: 0, to: flushed.count, by: 4) where flushed[i + 3] == 0 {
            flushed.replaceSubrange(i..<i + 4, with: [0, 0, 0, 0])
        }
        #expect(flushed != band.bytes, "the band has colour under alpha byte 0")
        let result = try PixelBuffer(rgba8: flushed, width: band.header.width, height: band.header.height)
        #expect(try ParityHarness.compare(golden: band, result).passed)
    }

    @Test func aBandIsOneSamplesRowsOfItsPack() throws {
        let pack = try #require(ParityPack.all.first { $0.ops.contains(.blur) })
        let bands = try pack.bands()
        #expect(pack.name == "display-blur-adjust-retouch" && bands.count == 20)
        #expect(bands.first { $0.op == .blur && $0.sample.name == "alpha-zero" }?.rows == 35..<42)
        #expect(bands.last?.rows == 133..<140 && bands.last?.op == .retouch)
        let sample = try #require(try ParityHarness.sampleSet(for: .adjust).first { $0.name == "random" })
        let golden = try ParityGolden.band(from: CPUGoldenTests.root, op: .adjust, sample: "random")
        let result = try ParityHarness.render(sample, on: CPUBackend())
        #expect(try golden.header.height == 7 && golden.bytes == result.rgba8(colorSpace: .sRGB))
        #expect(throws: RenderError.self) { try ParityGolden.band(from: CPUGoldenTests.root, op: .adjust, sample: "off-left") }
        #expect(throws: RenderError.self) { try golden.rows(6..<8) }
        let blurNames = try ParityHarness.sampleSet(for: .blur).map(\.name)
        let unknown = #expect(throws: RenderError.self) { try ParityGolden.band(from: CPUGoldenTests.root, op: .blur, sample: "nope") }
        guard case .raster(let message) = unknown else { Issue.record("not raster: \(String(describing: unknown))"); return }
        #expect(message.contains("\"nope\"") && blurNames.allSatisfy { message.contains($0) })
        #expect(throws: RenderError.self) { try golden.rows(3..<3) }
        #expect(throws: RenderError.self) { try golden.rows(-1..<2) }
    }

    @Test func linearBoundCatchesWhatBytesHide() throws {
        let a = try fill(2, 2, 0.5, 0.5, 0.5, 1)
        var b = a
        try b.setPixel(x: 1, y: 0, RGBA(r: 0.5, g: 0.5025, b: 0.5, a: 1))
        let result = try ParityHarness.compare(a, b, tolerance: ParityTolerance(bytes: 255, linear: 1e-3))
        #expect(!result.passed && result.worstLinearX == 1 && result.worstLinearY == 0)
        #expect(abs(result.worstLinearDelta - 0.0025) < 1e-6)
        // Alpha 0.5 and 0.5015 are both byte 128; only the linear bound sees it.
        let alpha = try ParityHarness.compare(fill(1, 1, 0, 0, 0, 0.5), fill(1, 1, 0, 0, 0, 0.5015), tolerance: .standard)
        #expect(alpha.worstByteDelta == 0 && !alpha.passed, "\(alpha)")
    }

    @Test func transparentPixelsAreLeftOutAndSizesMustMatch() throws {
        let a = try fill(2, 1, 0.9, 0.1, 0.4, 0), b = try fill(2, 1, 0, 0.7, 0, 0)
        let result = try ParityHarness.compare(a, b, tolerance: .standard)
        #expect(result.passed && result.worstLinearDelta == 0, "\(result)")
        let message = rasterMessage { _ = try ParityHarness.compare(a, fill(1, 2, 0, 0, 0, 1), tolerance: .standard) }
        #expect(message.contains("2x1") && message.contains("1x2"), "\(message)")
    }

    @Test func aCompositeSampleWithoutABackdropThrowsNamingIt() throws {
        let sample = ParitySample(name: "lonely", call: .composite(x: 0, y: 0, mode: .normal, opacity: 1),
                                  source: try fill(1, 1, 0, 0, 0, 1), backdrop: nil)
        let message = rasterMessage { _ = try ParityHarness.render(sample, on: FakeBackend(supports: [.composite])) }
        #expect(message.contains("lonely") && message.contains("backdrop"), "\(message)")
    }

    @Test func goldenErrorsSayWhatFailed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parity-\(UUID().uuidString)")
        let missing = rasterMessage { _ = try ParityGolden.read(from: root, op: .display, name: "random") }
        #expect(missing.contains("display/random.json"), "\(missing)")
        let undecodable = rasterMessage { _ = try ParityGolden(header: Data("{}".utf8), bytes: Data()) }
        #expect(undecodable.hasPrefix("golden header does not decode: ") && undecodable.count > 31, "\(undecodable)")
        let header = { (space: String, linear: String) in
            Data(#"{"width":1,"height":1,"colorSpace":"\#(space)","tolerance":{"bytes":2,"linear":\#(linear)}}"#.utf8)
        }
        let space = rasterMessage { _ = try ParityGolden(header: header("oklab", "0"), bytes: Data(count: 4)) }
        #expect(space.contains("color space") && space.contains("oklab"), "\(space)")
        let tolerance = rasterMessage { _ = try ParityGolden(header: header("sRGB", "-1"), bytes: Data(count: 4)) }
        #expect(tolerance.contains("tolerance.linear -1.0"), "\(tolerance)")
    }

    /// The message of the `RenderError.raster` that `body` throws, or "" when it throws nothing.
    private func rasterMessage(_ body: () throws -> Void) -> String {
        do { try body() } catch RenderError.raster(let message) { return message } catch { return "other: \(error)" }
        return ""
    }

    @Test func goldenRoundTripsThroughFilesAndChecksItsByteCount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sample = try #require(try ParityHarness.sampleSet(for: .blur).first)
        let golden = try ParityGolden(sample.source, tolerance: .nonSeparable)
        try golden.write(to: root, op: .blur, name: sample.name)
        let read = try ParityGolden.read(from: root, op: .blur, name: sample.name)
        #expect(read == golden && read.header.width == 9 && read.header.tolerance == .nonSeparable)
        #expect(try ParityHarness.compare(read.buffer(), sample.source, tolerance: .standard).worstByteDelta == 0)
        #expect(throws: RenderError.self) { try golden.write(to: root, op: .blur, name: "../escape") }
        #expect(throws: RenderError.self) { try ParityGolden.read(from: root, op: .blur, name: "missing") }
        let json = Data(#"{"width":2,"height":1,"colorSpace":"sRGB","tolerance":{"bytes":2,"linear":0.001}}"#.utf8)
        #expect(try ParityGolden(header: json, bytes: Data(count: 8)).bytes.count == 8)
        let exact = Data(#"{"width":1,"height":1,"colorSpace":"sRGB","tolerance":{"bytes":0,"linear":0}}"#.utf8)
        #expect(try ParityGolden(header: exact, bytes: Data(count: 4)).header.tolerance == ParityTolerance(bytes: 0, linear: 0))
        for count in [0, 7, 9, 16] {
            #expect(throws: RenderError.self) { try ParityGolden(header: json, bytes: Data(count: count)) }
        }
    }

    @Test func sampleSetIsDeterministicAndNamesItsEdgeCases() throws {
        for op in RenderOp.allCases where !RenderOp.notOnMetalYet.contains(op) {  // W1 sets are empty until filled
            let names = try ParityHarness.sampleSet(for: op).map(\.name)
            #expect(try ParityHarness.sampleSet(for: op) == ParityHarness.sampleSet(for: op))
            #expect(Set(names).count == names.count, "\(op): names are unique")
            #expect(Set(["random", "alpha-zero", "alpha-subnormal", "opaque-rows"]).isSubset(of: names))
            let placed = [RenderOp.composite, .blendSeparable, .blendNonSeparable, .retouch].contains(op)
            #expect(Set(["off-left", "off-top", "off-right", "off-bottom"]).isSubset(of: names) == placed, "\(op)")
        }
        let affine = try ParityHarness.sampleSet(for: .affine)
        #expect(try affine == ParityHarness.sampleSet(for: .affine) && affine.count == 10)
        #expect(Set(affine.map(\.name)).count == affine.count, "affine: names are unique")
        #expect(affine.allSatisfy { ($0.backdrop != nil) == $0.name.hasPrefix("through-") }, "affine: backdrop only when compositing")
        let tiny = try #require(try ParityHarness.sampleSet(for: .display).first { $0.name == "alpha-subnormal" })
        #expect(try tiny.source.pixel(x: 0, y: 0).a == 1e-45)
        let hue = try ParityHarness.sampleSet(for: .blendNonSeparable).map(\.name)
        #expect(hue.contains("mode-hue") && hue.contains("mode-luminosity") && !hue.contains("mode-multiply"))
    }

    @Test func w1FamiliesHaveEmptySetsAndOldFamiliesAreUnchanged() throws {
        for op in RenderOp.notOnMetalYet.subtracting([.affine]).sorted(by: { $0.rawValue < $1.rawValue }) {
            let names = try ParityHarness.sampleSet(for: op).map(\.name)
            // tone-pack filled `.color`: 11 colour cases on the four edge-case sources.
            #expect(names.count == (op == .color ? 44 : 0), "\(op) has no samples until its feature adds them")
            #expect(Set(names).count == names.count, "\(op): names are unique")
            #expect(try ParityHarness.sampleSet(for: op) == ParityHarness.sampleSet(for: op), "\(op)")
        }
        #expect(ParityPack.all.count == 7 && ParityPack.all.map(\.name) == ["display-blur-adjust-retouch", "composite-blendSeparable",
                                               "blendNonSeparable", "transform", "resample", "affine", "color"])
        // FNV-1a over each old family's names, calls and input Float bits: the goldens were cut from these.
        var counts: [String: Int] = [:], prints: [String: UInt64] = [:]
        for op in RenderOp.allCases where !RenderOp.notOnMetalYet.contains(op) {
            let samples = try ParityHarness.sampleSet(for: op)
            var hash: UInt64 = 0xCBF2_9CE4_8422_2325
            let mix = { (word: UInt64) in hash = (hash ^ word) &* 0x100_0000_01B3 }
            for sample in samples {
                "\(sample.name)|\(sample.call)".utf8.forEach { mix(UInt64($0)) }
                for buffer in [sample.source] + (sample.backdrop.map { [$0] } ?? []) {
                    for y in 0..<buffer.height {
                        for x in 0..<buffer.width {
                            let p = try buffer.pixel(x: x, y: y)
                            [p.r, p.g, p.b, p.a].forEach { mix(UInt64($0.bitPattern)) }
                        }
                    }
                }
            }
            (counts[op.rawValue], prints[op.rawValue]) = (samples.count, hash)
        }
        #expect(counts == ["display": 4, "composite": 8, "blendSeparable": 19, "blendNonSeparable": 12,
                           "transform": 4, "resample": 4, "blur": 4, "adjust": 4, "retouch": 8])
        #expect(prints == ["display": 0x880E_5D17_D8B7_2D19, "composite": 0xACF4_5786_E9D7_8CAE,
                           "blendSeparable": 0xD436_907E_83CE_792E, "blendNonSeparable": 0x67A2_3BE4_662C_04B8,
                           "transform": 0x020E_1289_31E3_A7E3, "resample": 0x0F53_4C7E_75E6_A1C9,
                           "blur": 0x1DA2_79A0_D5EE_C08D, "adjust": 0x0B81_CE5F_0F57_7E6D,
                           "retouch": 0xB5BB_BC99_07B5_9AB4], "\(prints)")
    }

    @Test func fuzzedGoldensThrowAndNeverTrap() throws {
        var rng = ParityRandom(seed: 0x601D)
        let fields = ["-1", "0", "3", "2", "9223372036854775807", "4611686018427387904", "1e999", "\"x\""]
        let spaces = ["\"sRGB\"", "\"displayP3\"", "\"oklab\"", "\"nope\"", "7"], linears = ["0.001", "-1", "1e999"]
        for _ in 0..<500 {
            let pick = { (from: [String]) in from.randomElement(using: &rng) ?? "1" }
            var text = "{\"width\":\(pick(fields)),\"height\":\(pick(fields)),\"colorSpace\":\(pick(spaces)),"
                + "\"tolerance\":{\"bytes\":2,\"linear\":\(pick(linears))}}"
            if Bool.random(using: &rng) { text = String(text.prefix(Int.random(in: 0...text.count, using: &rng))) }
            let bytes = Data((0..<Int.random(in: 0...40, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) })
            if let golden = try? ParityGolden(header: Data(text.utf8), bytes: bytes) {
                #expect(golden.bytes.count == golden.header.width * golden.header.height * 4 && golden.header.tolerance.linear >= 0)
            }
        }
    }
}
