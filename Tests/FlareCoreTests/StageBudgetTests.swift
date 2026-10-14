// StageBudgetTests.swift: the stage budgets QB-L6 (one render list per frame)
// and QB-L5 (one hit per pointer move) on a seeded scene of 1,000 shapes in 50
// layers with 10 instances. The split: 900 shapes sit directly on the scene's
// 50 layers (18 each), and each of the 10 instances places a symbol of 2
// layers x 5 shapes, so instances contribute 100. Shapes mix rectangles,
// rounded rectangles, ellipses and stars, half of them stroked, so the hit
// tolerance path flattens real cubics. Layers carry keyframed tracks so the
// list samples placements. Budgets are debug-build CI gates, median of runs.
import FlareCore
import Testing

@Suite struct StageBudgetTests {
    static let layerCount = 50
    static let shapesPerLayer = 18
    static let instanceCount = 10
    static let symbolLayers = 2
    static let shapesPerSymbolLayer = 5
    static let itemCount = layerCount * shapesPerLayer + instanceCount * symbolLayers * shapesPerSymbolLayer
    static let renderListBudget: Duration = .milliseconds(20)
    static let hitBudget: Duration = .milliseconds(10)
    static let frame = 12.0

    /// One seeded shape inside `size` x `size` around the origin of its layer.
    static func shape(_ rng: inout SplitMix64, size: Double) throws -> Shape {
        let x = Double.random(in: 0...size, using: &rng)
        let y = Double.random(in: 0...size, using: &rng)
        let w = Double.random(in: 4...40, using: &rng)
        let h = Double.random(in: 4...40, using: &rng)
        let rect = Rect(minX: x, minY: y, maxX: x + w, maxY: y + h)
        let path: Path
        switch Int.random(in: 0..<4, using: &rng) {
        case 0: path = try PathBuilders.rectangle(in: rect)
        case 1: path = try PathBuilders.rectangle(in: rect, cornerRadius: min(w, h) / 4)
        case 2: path = try PathBuilders.ellipse(in: rect)
        default: path = try PathBuilders.star(in: rect, points: 5, innerRatio: 0.5)
        }
        let color = Color(r: Double.random(in: 0...1, using: &rng), g: 0.4, b: 0.6)
        let stroke = Bool.random(using: &rng) ? Stroke(color: .black, width: Double.random(in: 1...4, using: &rng)) : nil
        return Shape(points: [], fill: .solid(color), path: path, stroke: stroke)
    }

    /// The seeded scene and the symbol its instances place.
    static func scene(seed: UInt64) throws -> (Scene, [Symbol]) {
        var rng = SplitMix64(seed: seed)
        var symbolLayerList: [Layer] = []
        for i in 0..<symbolLayers {
            var shapes: [Shape] = []
            for _ in 0..<shapesPerSymbolLayer { shapes.append(try shape(&rng, size: 60)) }
            symbolLayerList.append(Layer(id: "sym\(i)", name: "Symbol \(i)", shapes: shapes))
        }
        let symbol = Symbol(id: "badge", name: "Badge", layers: symbolLayerList)

        var layers: [Layer] = []
        for i in 0..<layerCount {
            var shapes: [Shape] = []
            for _ in 0..<shapesPerLayer { shapes.append(try shape(&rng, size: 500)) }
            let dx = Double.random(in: -20...20, using: &rng)
            let tracks = ["x": [Keyframe(frame: 0, value: 0), Keyframe(frame: 24, value: dx, easing: .easeInOut)]]
            var instances: [Instance] = []
            // Every fifth layer holds one instance: 10 instances over 50 layers.
            if i % (layerCount / instanceCount) == 0 {
                let place = Transform(x: Double.random(in: 0...450, using: &rng),
                                      y: Double.random(in: 0...300, using: &rng),
                                      scaleX: 1.5, scaleY: 1.5, rotation: Double.random(in: 0...90, using: &rng))
                instances.append(Instance(symbolID: symbol.id, transform: place))
            }
            layers.append(Layer(id: "L\(i)", name: "Layer \(i)", shapes: shapes, tracks: tracks, instances: instances))
        }
        return (Scene(id: "budget", name: "Budget", layers: layers), [symbol])
    }

    /// The median of `runs` timings of `body`.
    static func median(runs: Int, _ body: (Int) -> Void) -> Duration {
        let clock = ContinuousClock()
        var times: [Duration] = []
        for run in 0..<runs { times.append(clock.measure { body(run) }) }
        times.sort()
        return times[times.count / 2]
    }

    @Test func renderListWithinBudget() throws {
        let (scene, symbols) = try Self.scene(seed: 2026)
        let list = scene.renderList(at: Self.frame, symbols: symbols)
        #expect(list.items.count == Self.itemCount)
        #expect(Self.itemCount == 1_000)
        #expect(list.items.filter { !$0.address.hosts.isEmpty }.count == 100)

        var built = 0
        let median = Self.median(runs: 20) { run in
            built += scene.renderList(at: Self.frame + Double(run % 4), symbols: symbols).items.count
        }
        #expect(built == 20 * Self.itemCount)
        #expect(median <= Self.renderListBudget, "render list median \(median) over \(Self.renderListBudget)")
    }

    @Test func hitWithinBudget() throws {
        let (scene, symbols) = try Self.scene(seed: 2026)
        let list = scene.renderList(at: Self.frame, symbols: symbols)
        #expect(list.items.count == Self.itemCount)

        var rng = SplitMix64(seed: 5)
        let points = (0..<50).map { _ in
            Point(x: Double.random(in: -20...570, using: &rng), y: Double.random(in: -20...420, using: &rng))
        }
        var hits = 0
        let median = Self.median(runs: points.count) { run in
            if list.hit(points[run], tolerance: 4) != nil { hits += 1 }
        }
        // Seeded points both land on items and miss them, so both paths are timed.
        #expect(hits > 0 && hits < points.count)
        #expect(median <= Self.hitBudget, "hit median \(median) over \(Self.hitBudget)")
    }
}
