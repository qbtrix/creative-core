// PathFixtures.swift: paths for the edit and measure checks, built in code:
// star, ring, self-crossing figure-eight, 3-contour glyph and a seeded open
// 10,000-anchor scribble, lines and cubics only so contours round-trip exactly;
// and a closed quad loop for the split checks.
import FlareCore

private func pt(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }

enum PathFixtures {
    static let scribbleAnchors = 10_000

    static func star() throws -> Path {
        try PathBuilders.star(in: Rect(minX: 0, minY: 0, maxX: 100, maxY: 100), points: 5, innerRatio: 0.4)
    }

    static func ring() throws -> Path {
        let outer = try PathBuilders.ellipse(in: Rect(minX: 0, minY: 0, maxX: 100, maxY: 100))
        return Path(elements: try outer.elements + PathBuilders.ellipse(in: Rect(minX: 25, minY: 25, maxX: 75, maxY: 75)).elements)
    }

    static let figureEight = Path(elements: [
        .move(to: pt(50, 50)), .cubic(control1: pt(100, 0), control2: pt(100, 100), to: pt(50, 50)),
        .cubic(control1: pt(0, 0), control2: pt(0, 100), to: pt(50, 50)), .close,
    ])

    static let glyph = Path(elements: [
        .move(to: pt(0, 0)), .line(to: pt(60, 0)), .cubic(control1: pt(80, 0), control2: pt(80, 40), to: pt(60, 40)),
        .line(to: pt(0, 40)), .close,
        .move(to: pt(20, 10)), .cubic(control1: pt(30, 5), control2: pt(40, 15), to: pt(40, 20)), .line(to: pt(20, 30)), .close,
        .move(to: pt(70, 50)), .cubic(control1: pt(75, 60), control2: pt(85, 40), to: pt(90, 50)), .line(to: pt(100, 50)),
    ])

    /// One closed contour of two quads and a line, outside `all()`: contours raise quads.
    static let quadLoop = Path(elements: [
        .move(to: pt(0, 0)), .quad(control: pt(50, -30), to: pt(100, 0)), .quad(control: pt(130, 50), to: pt(100, 100)),
        .line(to: pt(0, 100)), .close,
    ])

    /// One open contour: a move and 9,999 random cubics.
    static func scribble(seed: UInt64 = 42) -> Path {
        var rng = SplitMix64(seed: seed)
        func random() -> Point { pt(Double.random(in: 0...1000, using: &rng), Double.random(in: 0...1000, using: &rng)) }
        let start = PathElement.move(to: random())
        return Path(elements: [start] + (1..<scribbleAnchors).map { _ in
            .cubic(control1: random(), control2: random(), to: random())
        })
    }

    static func all() throws -> [(String, Path)] {
        [("star", try star()), ("ring", try ring()), ("figureEight", figureEight), ("glyph", glyph), ("scribble", scribble())]
    }
}
