// PathPropertySupport.swift: seeded generators (paths of lines, quads and
// cubics; hostile paths with a NaN or infinite coordinate; dash patterns and
// phases) for the measure, trim and dash property checks.
import FlareCore
import Testing

enum PathGen {
    static func point(_ rng: inout SplitMix64) -> Point {
        Point(x: Double.random(in: 0...100, using: &rng), y: Double.random(in: 0...100, using: &rng))
    }

    /// One to three contours of one to six segments, each closed half the time.
    static func path(_ rng: inout SplitMix64) -> Path {
        var elements: [PathElement] = []
        for _ in 0..<Int.random(in: 1...3, using: &rng) {
            elements.append(.move(to: point(&rng)))
            for _ in 0..<Int.random(in: 1...6, using: &rng) {
                switch Int.random(in: 0...2, using: &rng) {
                case 0: elements.append(.line(to: point(&rng)))
                case 1: elements.append(.quad(control: point(&rng), to: point(&rng)))
                default: elements.append(.cubic(control1: point(&rng), control2: point(&rng), to: point(&rng)))
                }
            }
            if Bool.random(using: &rng) { elements.append(.close) }
        }
        return Path(elements: elements)
    }

    /// A random path with one coordinate replaced by NaN or an infinity.
    static func hostile(_ rng: inout SplitMix64) -> Path {
        var elements = path(&rng).elements
        let bad = [Double.nan, .infinity, -.infinity][Int.random(in: 0...2, using: &rng)]
        let i = Int.random(in: 0..<elements.count, using: &rng)
        if case .move = elements[i] { elements[i] = .move(to: Point(x: bad, y: 0)) } else { elements[i] = .line(to: Point(x: 0, y: bad)) }
        return Path(elements: elements)
    }

    /// One to six entries in 0.5...20.
    static func pattern(_ rng: inout SplitMix64) -> [Double] {
        (0..<Int.random(in: 1...6, using: &rng)).map { _ in Double.random(in: 0.5...20, using: &rng) }
    }

    static func phase(_ rng: inout SplitMix64) -> Double { Double.random(in: -50...50, using: &rng) }
}

@Suite struct PathPropertySupportTests {
    @Test func generatorsAreDeterministicPerSeed() {
        var a = SplitMix64(seed: 9), b = SplitMix64(seed: 9), c = SplitMix64(seed: 10)
        let one = (0..<20).map { _ in PathGen.path(&a) }, two = (0..<20).map { _ in PathGen.path(&b) }
        #expect(one == two && one != (0..<20).map { _ in PathGen.path(&c) })
        #expect(PathGen.pattern(&a) == PathGen.pattern(&b) && PathGen.phase(&a) == PathGen.phase(&b))
        #expect(PathGen.hostile(&a).elements.count == PathGen.hostile(&b).elements.count)
    }
}
