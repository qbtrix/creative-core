// RasterThroughputBudgetTests.swift: the release budgets for whole-image
// raster work on 12 MP (4000 x 3000), issue #309: Copy (`rgba8()`), Paste
// (`init(rgba8:)`), Merge Down and Flatten (the in-place composite) on one
// core and as four 4000 x 750 bands at once, and one 256 px tile encode.
// Debug builds skip the suite (CoreRaster's loops are about 20 times slower
// there); the equivalence tests in DisplayBytesFastPathTests and
// CompositeInPlaceTests carry the debug gate. Inputs are built once per test,
// outside the timed region. Each row prints its median as
// `budget <row>: <ms> ms (budget <ms> ms)` and gates on it; reported rows
// print `(report only)`.
import CoreRaster
import Dispatch
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

private let width = 4000, height = 3000
private let bandCount = 4, bandHeight = 750
/// Timed runs per row; the median is gated.
private let runs = 5

/// A seeded 12 MP layer: straight colors in 0...1 and alpha in `alpha`,
/// premultiplied as `PixelBuffer` stores them.
private func seededLayer(seed: UInt64, alpha: ClosedRange<Float>) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    var buffer = try PixelBuffer(width: width, height: height)
    for y in 0..<height {
        for x in 0..<width {
            let straight = RGBA(r: .random(in: 0...1, using: &rng), g: .random(in: 0...1, using: &rng),
                                b: .random(in: 0...1, using: &rng), a: .random(in: alpha, using: &rng))
            try buffer.setPixel(x: x, y: y, straight.premultiplied())
        }
    }
    return buffer
}

/// Band `band` of a 12 MP buffer, as its own buffer.
private func band(_ band: Int, of buffer: PixelBuffer) throws -> PixelBuffer {
    try buffer.cropped(x: 0, y: band * bandHeight, width: width, height: bandHeight)
}

private func milliseconds(_ d: Duration) -> String {
    let ms = Double(d.components.seconds) * 1e3 + Double(d.components.attoseconds) / 1e15
    return "\((ms * 1000).rounded() / 1000)"
}

private func median(_ times: [Duration]) -> Duration {
    let sorted = times.sorted()
    return sorted.isEmpty ? .zero : sorted[sorted.count / 2]
}

/// Prints the median of `times` and, with a budget, expects it within.
private func check(_ row: String, _ times: [Duration], budget: Duration?) {
    let m = median(times)
    if let budget {
        print("budget \(row): \(milliseconds(m)) ms (budget \(milliseconds(budget)) ms)")
        #expect(m <= budget, "\(row): median \(m) over \(budget)")
    } else {
        print("budget \(row): \(milliseconds(m)) ms (report only)")
    }
}

/// One value per slot, each written by one `concurrentPerform` iteration.
private final class Slots<T>: @unchecked Sendable {
    private let base: UnsafeMutablePointer<T?>
    let count: Int

    init(_ values: [T?]) {
        count = values.count
        base = .allocate(capacity: count)
        base.initialize(from: values, count: count)
    }

    deinit {
        base.deinitialize(count: count)
        base.deallocate()
    }

    func put(_ i: Int, _ value: T) { base[i] = value }
    /// Moves the value out, so a buffer taken here is uniquely owned.
    func take(_ i: Int) -> T? { base[i].take() }
}

private struct BandMissing: Error {}

/// Runs `work` for every band at once, each on its own thread, and returns
/// each band's own wall time and result.
private func inBands<T>(_ work: @Sendable (Int) throws -> T) throws -> [(time: Duration, value: T)] {
    let out = Slots<Result<(time: Duration, value: T), any Error>>(Array(repeating: nil, count: bandCount))
    DispatchQueue.concurrentPerform(iterations: bandCount) { band in
        let clock = ContinuousClock()
        let start = clock.now
        let result = Result { try work(band) }
        let time = clock.now - start
        out.put(band, result.map { (time: time, value: $0) })
    }
    return try (0..<bandCount).map { band in
        guard let result = out.take(band) else { throw BandMissing() }
        return try result.get()
    }
}

/// The slowest band's time in each of `runs` runs of `work`, and the last run's results.
private func bandRuns<T>(_ work: @Sendable (Int) throws -> T) throws -> (times: [Duration], last: [T]) {
    var times: [Duration] = []
    var last: [T] = []
    for _ in 0..<runs {
        let results = try inBands(work)
        times.append(results.map(\.time).max() ?? .zero)
        last = results.map(\.value)
    }
    return (times, last)
}

/// Serialized, so no two 12 MP runs share cores or memory bandwidth.
@Suite(.serialized, .enabled(if: optimized, "12 MP timing needs an optimized build"))
struct RasterThroughputBudgetTests {
    let clock = ContinuousClock()

    @Test func copyAndPasteWithinBudget() throws {
        let layer = try seededLayer(seed: 309, alpha: 0.05...0.95)

        var bytes: [UInt8] = []
        check("copy rgba8 12MP one core", try (0..<runs).map { _ in
            try clock.measure { bytes = try layer.rgba8() }
        }, budget: .milliseconds(30))
        var pasted = layer
        check("paste init(rgba8:) 12MP one core", try (0..<runs).map { _ in
            try clock.measure { pasted = try PixelBuffer(rgba8: bytes, width: width, height: height) }
        }, budget: .milliseconds(30))

        let encoded = try bandRuns { band in
            try layer.rgba8(x: 0, y: band * bandHeight, width: width, height: bandHeight)
        }
        check("copy rgba8 band 4000x750 four cores", encoded.times, budget: .milliseconds(10))
        // The bands do the whole picture's work: together they are its bytes.
        #expect(encoded.last.flatMap { $0 } == bytes)

        let bandBytes = encoded.last
        let decoded = try bandRuns { band in
            try PixelBuffer(rgba8: bandBytes[band], width: width, height: bandHeight)
        }
        check("paste init(rgba8:) band 4000x750 four cores", decoded.times, budget: .milliseconds(10))
        for (i, part) in decoded.last.enumerated() {
            #expect(try part == band(i, of: pasted))
        }
    }

    @Test func mergeAndFlattenWithinBudget() throws {
        let lower = try seededLayer(seed: 1, alpha: 0.05...0.95)
        let upper = try seededLayer(seed: 2, alpha: 0.05...0.95)
        let top = try seededLayer(seed: 3, alpha: 0.05...0.95)

        /// Times `merge` on a fresh, uniquely owned copy of `lower` in each run.
        func timed(_ merge: (inout PixelBuffer) throws -> Void) throws -> (times: [Duration], last: PixelBuffer) {
            var times: [Duration] = []
            var result = lower
            for _ in 0..<runs {
                // A full-size crop is a new, uniquely owned buffer, so the
                // in-place composite never copies on its first write.
                var backdrop = try lower.cropped(x: 0, y: 0, width: width, height: height)
                times.append(try clock.measure { try merge(&backdrop) })
                result = backdrop
            }
            return (times, result)
        }

        let merged = try timed { try $0.composite(upper, x: 0, y: 0, mode: .normal, opacity: 1) }
        check("merge down composite 12MP one core", merged.times, budget: .milliseconds(60))
        #expect(merged.last != lower)
        let flattened = try timed {
            try $0.composite(upper, x: 0, y: 0, mode: .normal, opacity: 1)
            try $0.composite(top, x: 0, y: 0, mode: .normal, opacity: 1)
        }
        check("flatten three layers 12MP one core", flattened.times, budget: .milliseconds(120))

        let opaque = try seededLayer(seed: 4, alpha: 1...1)
        check("merge down opaque row copy 12MP one core", try timed {
            try $0.composite(opaque, x: 0, y: 0, mode: .normal, opacity: 1)
        }.times, budget: nil)
        check("merge down multiply 0.37 12MP one core", try timed {
            try $0.composite(upper, x: 0, y: 0, mode: .multiply, opacity: 0.37)
        }.times, budget: nil)

        let sources = try (0..<bandCount).map { try band($0, of: upper) }
        var times: [Duration] = []
        var last: [PixelBuffer] = []
        for _ in 0..<runs {
            // Fresh backdrops each run, moved into the band that owns them.
            let backdrops = Slots<PixelBuffer>(try (0..<bandCount).map { try band($0, of: lower) })
            let results = try inBands { i in
                guard var backdrop = backdrops.take(i) else { throw BandMissing() }
                try backdrop.composite(sources[i], x: 0, y: 0, mode: .normal, opacity: 1)
                return backdrop
            }
            times.append(results.map(\.time).max() ?? .zero)
            last = results.map(\.value)
        }
        check("merge down composite band 4000x750 four cores", times, budget: .milliseconds(20))
        for (i, part) in last.enumerated() {
            #expect(try part == band(i, of: merged.last))
        }
    }

    @Test func tileEncodeWithinBudget() throws {
        let layer = try seededLayer(seed: 256, alpha: 0.05...0.95)
        let x = 2048, y = 1536, side = 256
        var tile: [UInt8] = []
        let times = try (0..<25).map { _ in
            try clock.measure { tile = try layer.rgba8(x: x, y: y, width: side, height: side) }
        }
        check("tile encode 256px of 12MP", times, budget: .microseconds(500))
        #expect(try tile == layer.cropped(x: x, y: y, width: side, height: side).rgba8())
    }
}
