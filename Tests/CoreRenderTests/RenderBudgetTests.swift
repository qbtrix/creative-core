// RenderBudgetTests.swift: the packet's dispatcher-overhead row (render-backend
// RB-7). A 12 MP (4000 x 3000) `.normal` composite at opacity 0.8 through a
// `RenderDispatcher` with no preferred backend (so the CPU backend runs it)
// must take at most 2% more than CoreRaster's in-place composite, median of 5
// runs each. A copy of the backdrop anywhere on the way (the store, the
// dispatcher) costs far more than 2%. Debug builds skip the suite, as the other
// release budgets do. Each call runs once untimed to warm caches and code, then
// the two take turns, the direct call first on even rounds and second on odd
// ones, each on a fresh uniquely owned backdrop made outside the clock, so
// drift in the machine and the cost of going first hit both alike.
import CoreRaster
import CoreRender
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

/// Serialized, so no two 12 MP runs share cores or memory bandwidth.
@Suite(.serialized, .enabled(if: optimized, "12 MP timing needs an optimized build"))
struct RenderBudgetTests {
    /// A seeded 12 MP layer, premultiplied, alpha in 0.05...0.95.
    private func layer(seed: UInt64) throws -> PixelBuffer {
        var rng = SplitMix64(seed: seed)
        var buffer = try PixelBuffer(width: 4000, height: 3000)
        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                let a = Float.random(in: 0.05...0.95, using: &rng)
                try buffer.setPixel(x: x, y: y, RGBA(r: .random(in: 0...a, using: &rng),
                                                     g: .random(in: 0...a, using: &rng),
                                                     b: .random(in: 0...a, using: &rng), a: a))
            }
        }
        return buffer
    }

    @Test func dispatcherCompositeWithinTwoPercentOfDirect() throws {
        let clock = ContinuousClock()
        let lower = try layer(seed: 7), upper = try layer(seed: 8)
        let dispatcher = RenderDispatcher(preferred: nil, fallback: CPUBackend())
        let source = try dispatcher.surface(upper)
        defer { dispatcher.release(source) }
        var direct: [Duration] = [], routed: [Duration] = []
        var directResult = lower, routedResult = lower
        // A full-size crop is a new buffer with one owner, so nothing copies on the first write.
        let fresh = { try lower.cropped(x: 0, y: 0, width: lower.width, height: lower.height) }
        let runDirect = {
            var backdrop = try fresh()
            let time = try clock.measure { try backdrop.composite(upper, x: 0, y: 0, mode: .normal, opacity: 0.8) }
            directResult = backdrop
            return time
        }
        let runRouted = {
            var target = try dispatcher.surface(fresh())
            defer { dispatcher.release(target) }
            let time = try clock.measure {
                try dispatcher.composite(source, onto: &target, x: 0, y: 0, mode: .normal, opacity: 0.8)
            }
            routedResult = try dispatcher.read(target)
            return time
        }
        _ = try (runDirect(), runRouted())
        for round in 0..<5 {
            if round % 2 == 0 {
                direct.append(try runDirect())
                routed.append(try runRouted())
            } else {
                routed.append(try runRouted())
                direct.append(try runDirect())
            }
        }
        let (d, r) = (direct.sorted()[2], routed.sorted()[2])
        let overhead = (r / d - 1) * 100
        print("budget dispatcher composite 12MP: \(r) vs direct \(d), overhead \(overhead)% (budget 2%)")
        #expect(overhead <= 2, "dispatcher \(r) is \(overhead)% over direct \(d)")
        #expect(routedResult == directResult, "the dispatcher changed a pixel")
    }
}
