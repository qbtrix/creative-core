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
        for count in [0, 7, 9, 16] {
            #expect(throws: RenderError.self) { try ParityGolden(header: json, bytes: Data(count: count)) }
        }
    }

    @Test func sampleSetIsDeterministicAndNamesItsEdgeCases() throws {
        for op in RenderOp.allCases {
            let names = try ParityHarness.sampleSet(for: op).map(\.name)
            #expect(try ParityHarness.sampleSet(for: op) == ParityHarness.sampleSet(for: op))
            #expect(Set(names).count == names.count, "\(op): names are unique")
            #expect(Set(["random", "alpha-zero", "alpha-subnormal", "opaque-rows"]).isSubset(of: names))
            let placed = [RenderOp.composite, .blendSeparable, .blendNonSeparable, .retouch].contains(op)
            #expect(Set(["off-left", "off-top", "off-right", "off-bottom"]).isSubset(of: names) == placed, "\(op)")
        }
        let tiny = try #require(try ParityHarness.sampleSet(for: .display).first { $0.name == "alpha-subnormal" })
        #expect(try tiny.source.pixel(x: 0, y: 0).a == 1e-45)
        let hue = try ParityHarness.sampleSet(for: .blendNonSeparable).map(\.name)
        #expect(hue.contains("mode-hue") && hue.contains("mode-luminosity") && !hue.contains("mode-multiply"))
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
