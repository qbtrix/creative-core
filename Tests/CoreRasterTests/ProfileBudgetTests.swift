// ProfileBudgetTests.swift: the colour-profiles budgets (CP-9, quality rows
// "Convert a photo" and "16-bit costs little"): converting a 24 MP buffer from
// the walk's wide-gamut profile into the working space takes at most 150 ms,
// and opening a 12 MP 16-bit PSD at most 1.3 times the same 8-bit open.
// The packet's budgets are release, reported: an optimized build gates on
// them (the Mac finisher runs them there), and a debug build, which is what
// `scripts/ci` runs in its parallel pass, only reports, so no wall-clock check
// can flake the gate. Debug also runs a sixteenth of the pixels: the loops are
// many times slower there, and the debug run proves the path works and that
// its results are right, not its speed. Times are wall-clock medians of
// `runs`, each run's earlier result freed before the clock starts, printed as
// `budget <row>: <ms> ms (budget <ms> ms)` or `(report only, debug)`.
// Fixture pixels are seeded noise read through `init(rgba8:)`.
import CoreColor
import CoreRaster
import Foundation
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

private let runs = 3

private func milliseconds(_ d: Duration) -> String {
    let ms = Double(d.components.seconds) * 1e3 + Double(d.components.attoseconds) / 1e15
    return "\((ms * 1000).rounded() / 1000)"
}

/// The median of `runs` timings of `body`, each after an untimed `free`.
private func median(free: () -> Void, _ body: () throws -> Void) throws -> Duration {
    let clock = ContinuousClock()
    var wall: [Duration] = []
    for _ in 0..<runs {
        free()
        wall.append(try clock.measure(body))
    }
    return wall.sorted()[runs / 2]
}

/// Prints `row` and, in an optimized build, expects `time` within `budget`.
private func report(_ row: String, _ time: Duration, budget: Duration) {
    let suffix = optimized ? "budget \(milliseconds(budget)) ms" : "report only, debug; budget \(milliseconds(budget)) ms in release"
    print("budget \(row): \(milliseconds(time)) ms (\(suffix))")
    if optimized { #expect(time <= budget, "\(row): median \(time) over \(budget)") }
}

/// A seeded noise buffer, `alpha` 255 for opaque or else seeded too.
private func noise(width: Int, height: Int, seed: UInt64, opaque: Bool) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { raw in
        for i in stride(from: 0, to: raw.count, by: 8) { raw.storeBytes(of: rng.next(), toByteOffset: i, as: UInt64.self) }
    }
    if opaque { for i in stride(from: 3, to: bytes.count, by: 4) { bytes[i] = 255 } }
    return try PixelBuffer(rgba8: bytes, width: width, height: height)
}

/// Serialized, so no two large runs share cores or memory bandwidth.
@Suite(.serialized) struct ProfileBudgetTests {
    /// Debug runs a quarter of each side.
    static let scale = optimized ? 1 : 4

    @Test func convert24MP() throws {
        let width = 6000 / Self.scale, height = 4000 / Self.scale
        let photo = try noise(width: width, height: height, seed: 0xC9_0001, opaque: false)
        var working = photo
        let time = try median(free: { working = photo }) {
            working = try photo.converted(from: ProfileWalkTests.wide, to: .linearSRGB)
        }
        report("convert \(width)x\(height) wide to working", time, budget: .milliseconds(150))
        // The timed result is the conversion, pixel for pixel, on a sample of pixels.
        let transform = try ProfileTransform(from: ProfileWalkTests.wide, to: .linearSRGB)
        for (x, y) in [(0, 0), (width - 1, height - 1), (width / 2, height / 3), (17, 5)] {
            let p = try photo.pixel(x: x, y: y), q = try working.pixel(x: x, y: y)
            #expect(q.a == p.a)
            guard p.a > 0 else { #expect(q == p); continue }
            let s = p.unpremultiplied(), encoded = [s.r, s.g, s.b].map { TransferCurve.encode(Double($0)) }
            let want = transform.apply(Color3(encoded[0], encoded[1], encoded[2]))
            let got = q.unpremultiplied()
            #expect(abs(Double(got.r) - want.c0) < 1e-4 && abs(Double(got.g) - want.c1) < 1e-4
                    && abs(Double(got.b) - want.c2) < 1e-4, "(\(x), \(y)): \(got) against \(want)")
        }
    }

    @Test func deepOpen() throws {
        let width = 4000 / Self.scale, height = 3000 / Self.scale
        let pixels = try noise(width: width, height: height, seed: 0xC9_0002, opaque: true)
        func file(_ bits: Int) throws -> Data {
            try PSD.write(LayeredImage(width: width, height: height, nodes: [.pixels(PixelLayer(name: "Photo", pixels: pixels))],
                                       composite: pixels, bitsPerChannel: bits, profile: ProfileWalkTests.wide))
        }
        let eight = try file(8), sixteen = try file(16)
        var image = LayeredImage(width: 1, height: 1)
        let free = { image = LayeredImage(width: 1, height: 1) }
        let time8 = try median(free: free) { image = try PSD.read(eight) }
        #expect(image.bitsPerChannel == 8 && image.width == width && image.profile == ProfileWalkTests.wide)
        let time16 = try median(free: free) { image = try PSD.read(sixteen) }
        #expect(image.bitsPerChannel == 16 && image.width == width && image.profile == ProfileWalkTests.wide)
        #expect(try image.composite?.pixel(x: width / 2, y: height / 2) == pixels.pixel(x: width / 2, y: height / 2),
                "16 bits hold the 8-bit noise exactly")
        print("budget open \(width)x\(height) 8-bit PSD: \(milliseconds(time8)) ms (the reference)")
        report("open \(width)x\(height) 16-bit PSD", time16, budget: time8 * 1.3)
    }
}
