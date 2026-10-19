// RetouchBudgetTests.swift: the retouch-heal budgets (RH-7, quality rows
// "Heal at dab speed" and "Remove a spot"): on the walk's 2400 x 1600 spotted
// photo, healing a 200 px dab in place takes at most 12 ms, filling a 300 x 300 spot
// from its surroundings at most 400 ms, and a 200 px midtone dodge dab at most
// 1 ms. The packet's budgets are release, reported: an optimized build gates
// on them (the Mac finisher runs them there), and a debug build, which is what
// `scripts/ci` runs in its parallel pass, only reports, so no wall-clock check
// can flake the gate. Debug also runs a quarter of each side (photo, dab and
// spot): the loops are many times slower there, and the debug run proves the
// path works and that its result is right, not its speed. Times are
// wall-clock medians of `runs`, each run's earlier result freed before the
// clock starts, printed as `budget <row>: <ms> ms (budget <ms> ms)` or
// `(report only, debug)`.
import CoreRaster
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

/// Serialized, so no two large runs share cores or memory bandwidth.
@Suite(.serialized) struct RetouchBudgetTests {
    /// Debug runs a quarter of each side.
    static let scale = optimized ? 1 : 4
    static let width = 2400 / scale, height = 1600 / scale

    static func photo() throws -> RetouchFixtures.SpottedPhoto {
        try RetouchFixtures.spottedPhoto(width: width, height: height, seed: 0x5EA1)
    }

    @Test func healDab() throws {
        let photo = try Self.photo()
        let r = 100 / Self.scale, cx = Self.width / 2, cy = Self.height / 2, shift = -300 / Self.scale
        let dab = try RetouchFixtures.disc(width: Self.width, height: Self.height, centerX: Double(cx),
                                           centerY: Double(cy), radius: Double(r), hardness: 0.8)
        // A brush heals in place: each run starts on its own copy, as toneDab's does.
        let corner = try photo.spotted.pixel(x: 0, y: 0)
        var healed = photo.spotted
        let time = try median(free: {
            healed = photo.spotted
            try? healed.setPixel(x: 0, y: 0, corner)
        }) {
            try healed.heal(offset: (dx: shift, dy: shift), through: dab)
        }
        report("heal \(2 * r) px dab on \(Self.width)x\(Self.height)", time, budget: .milliseconds(12))
        // The timed heal removed spot 2's dark centre and kept the pixels outside its bounds.
        #expect(try healed.pixel(x: cx, y: cy) != RetouchFixtures.spotColor)
        #expect(try healed.pixel(x: cx + r + 2, y: cy) == photo.spotted.pixel(x: cx + r + 2, y: cy))
    }

    @Test func removeSpot() throws {
        let photo = try Self.photo()
        let r = 150.0 / Double(Self.scale), cx = Double(Self.width) / 4, cy = Double(Self.height) / 2
        let hole = try RetouchFixtures.disc(width: Self.width, height: Self.height, centerX: cx, centerY: cy, radius: r)
        var filled = photo.spotted
        let time = try median(free: { filled = photo.spotted }) {
            filled = try photo.spotted.filledFromSurroundings(hole, seed: 1)
        }
        report("fill \(Int(2 * r))x\(Int(2 * r)) spot on \(Self.width)x\(Self.height)", time, budget: .milliseconds(400))
        // The timed fill left no dark spot pixel in the hole.
        #expect(try RetouchWalkTests.luma(filled.pixel(x: Int(cx), y: Int(cy))) > 0.3)
    }

    @Test func toneDab() throws {
        let photo = try Self.photo()
        let r = 100 / Self.scale, x = Self.width / 2 - r, y = Self.height / 4 - r
        let dab = try RetouchFixtures.roundDab(radius: r, hardness: 0.6)
        // Each run starts on its own copy, written once untimed, so the timed
        // dab never pays for the copy-on-write of the whole photo.
        let corner = try photo.clean.pixel(x: 0, y: 0)
        var dodged = photo.clean
        let time = try median(free: {
            dodged = photo.clean
            try? dodged.setPixel(x: 0, y: 0, corner)
        }) {
            try dodged.dodge(dab, x: x, y: y, range: .midtones, exposure: 0.5)
        }
        report("dodge \(2 * r) px dab", time, budget: .milliseconds(1))
        // The timed dab lifted the midtone texture at its centre.
        let before = try photo.clean.pixel(x: x + r, y: y + r), after = try dodged.pixel(x: x + r, y: y + r)
        #expect(RetouchWalkTests.luma(after) > RetouchWalkTests.luma(before))
    }
}
