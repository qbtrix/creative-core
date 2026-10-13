// PNGExportPlanTests.swift: PNG frame export planning (frames, times, pixel
// sizes, file names), typed errors for bad input, and a seeded fuzz test.
import FlareCore
import Testing

@Suite struct PNGExportPlanTests {
    static let scene = Scene(id: "s", name: "Main", fps: 24, durationFrames: 48, width: 550, height: 400)

    @Test func everyFrameAtScaleTwo() throws {
        let plan = try PNGExportPlan.plan(scene: Self.scene, frames: 0...47, scale: 2)
        #expect(plan.count == 48)
        #expect(plan.map(\.frame) == Array(0...47))
        let entry = try #require(plan.dropFirst(24).first)
        #expect(entry.frame == 24)
        #expect(entry.time == 1.0)
        #expect(entry.pixelWidth == 1100)
        #expect(entry.pixelHeight == 800)
        #expect(plan.first?.fileName == "frame_0000.png")
        #expect(plan.last?.fileName == "frame_0047.png")
    }

    @Test func stepSkipsFrames() throws {
        let plan = try PNGExportPlan.plan(scene: Self.scene, frames: 0...47, scale: 1, step: 10)
        #expect(plan.map(\.frame) == [0, 10, 20, 30, 40])
        #expect(plan.map(\.fileName) == ["frame_0000.png", "frame_0010.png", "frame_0020.png",
                                         "frame_0030.png", "frame_0040.png"])
    }

    @Test func sizeRoundsAndNamesGrowPastFourDigits() throws {
        var scene = Self.scene
        scene.width = 101
        scene.durationFrames = 12_345
        let plan = try PNGExportPlan.plan(scene: scene, frames: 12_345...12_345, scale: 0.5)
        #expect(plan.count == 1)
        let entry = try #require(plan.first)
        #expect(entry.frame == 12_345)
        #expect(entry.time == 12_345.0 / 24)
        #expect(entry.pixelWidth == 51)
        #expect(entry.pixelHeight == 200)
        #expect(entry.fileName == "frame_12345.png")
    }

    @Test func lastFrameOfDurationIsInRange() throws {
        // #96: the range must lie in 0...durationFrames, so durationFrames itself is allowed.
        let plan = try PNGExportPlan.plan(scene: Self.scene, frames: 40...48, scale: 1, step: 4)
        #expect(plan.map(\.frame) == [40, 44, 48])
        #expect(plan.last?.fileName == "frame_0048.png")
    }

    @Test func steppedEntriesTakeTimeFromTheirFrame() throws {
        let plan = try PNGExportPlan.plan(scene: Self.scene, frames: 6...47, scale: 1, step: 12)
        #expect(plan.map(\.frame) == [6, 18, 30, 42])
        for entry in plan {
            #expect(entry.time == (try Timeline.time(ofFrame: entry.frame, fps: Self.scene.fps)))
        }
        #expect(plan.map(\.time) == [0.25, 0.75, 1.25, 1.75])
    }

    @Test func sizeAtThePixelLimitIsAllowed() throws {
        let side = Double(PNGExportPlan.maxPixels)
        let scene = Scene(id: "s", name: "Big", fps: 24, durationFrames: 1, width: side / 4, height: 1)
        let entry = try #require(try PNGExportPlan.plan(scene: scene, frames: 0...0, scale: 4).first)
        #expect(entry.pixelWidth == PNGExportPlan.maxPixels)
        #expect(entry.pixelHeight == 4)
        #expect(throws: PNGExportError.invalidSize(width: side + 4, height: 4)) {
            try PNGExportPlan.plan(scene: Scene(id: "s", name: "Big", fps: 24, durationFrames: 1,
                                                width: side / 4 + 1, height: 1), frames: 0...0, scale: 4)
        }
    }

    @Test func badInputThrows() {
        let s = Self.scene
        #expect(throws: PNGExportError.frameOutOfRange(-1...10)) {
            try PNGExportPlan.plan(scene: s, frames: -1...10, scale: 1)
        }
        #expect(throws: PNGExportError.frameOutOfRange(0...49)) {
            try PNGExportPlan.plan(scene: s, frames: 0...49, scale: 1)
        }
        #expect(throws: PNGExportError.invalidStep(0)) {
            try PNGExportPlan.plan(scene: s, frames: 0...47, scale: 1, step: 0)
        }
        #expect(throws: PNGExportError.invalidStep(-2)) {
            try PNGExportPlan.plan(scene: s, frames: 0...47, scale: 1, step: -2)
        }
        for scale in [0, -1, Double.nan, .infinity] {
            #expect(throws: PNGExportError.self) { try PNGExportPlan.plan(scene: s, frames: 0...1, scale: scale) }
        }
        #expect(throws: PNGExportError.invalidSize(width: 5_500_000, height: 4_000_000)) {
            try PNGExportPlan.plan(scene: s, frames: 0...1, scale: 10_000)
        }
        var bad = s
        bad.fps = 0
        #expect(throws: PNGExportError.invalidFPS(0)) { try PNGExportPlan.plan(scene: bad, frames: 0...1, scale: 1) }
        bad = s
        bad.width = .nan
        #expect(throws: PNGExportError.self) { try PNGExportPlan.plan(scene: bad, frames: 0...1, scale: 1) }
        bad = s
        bad.durationFrames = Int.max
        #expect(throws: PNGExportError.tooManyFrames(Int.max / 2 + 1)) {
            try PNGExportPlan.plan(scene: bad, frames: 0...Int.max, scale: 1, step: 2)
        }
    }

    @Test func fuzzNeverCrashes() {
        var rng = SplitMix64(seed: 44)
        let ints = [Int.min, -1, 0, 1, 2, 7, 24, 1000, 1 << 40, Int.max]
        let doubles = [-1, 0, 1e-9, 0.5, 1, 3, 1e6, 1e300, .nan, .infinity, -.infinity]
        func anyInt(_ rng: inout SplitMix64) -> Int {
            Bool.random(using: &rng) ? ints.randomElement(using: &rng) ?? 0 : Int.random(in: -5...200, using: &rng)
        }
        for _ in 0..<2000 {
            let scene = Scene(id: "s", name: "S", fps: anyInt(&rng), durationFrames: anyInt(&rng),
                              width: doubles.randomElement(using: &rng) ?? 1,
                              height: Double.random(in: -10...2000, using: &rng))
            let a = anyInt(&rng)
            let b = anyInt(&rng)
            let scale = Bool.random(using: &rng) ? doubles.randomElement(using: &rng) ?? 1 : Double.random(in: 0...4, using: &rng)
            let step = anyInt(&rng)
            do {
                let plan = try PNGExportPlan.plan(scene: scene, frames: min(a, b)...max(a, b), scale: scale, step: step)
                #expect(!plan.isEmpty && plan.count <= PNGExportPlan.maxFrames)
                #expect(plan.allSatisfy { $0.frame >= min(a, b) && $0.frame <= max(a, b) && $0.pixelWidth >= 1 })
            } catch {
                #expect(error is PNGExportError)
            }
        }
    }
}
