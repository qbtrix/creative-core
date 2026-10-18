import Foundation
import Testing
@testable import FlareCore

/// SVG path data to `Path` (VI-4): every command, implicit repeats, the number grammar and arcs as cubics.
struct SVGPathDataTests {
    /// VI-4 replaces this body with `try SVGPathData.path(d).elements`.
    func path(_ d: String) throws -> [PathElement] { throw ImportError.unsupported("SVGPathData not built") }
    func p(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }

    @Test(.disabled("waits on VI-4")) func commandsRepeatsAndNumbers() throws {
        #expect(try path("M10 20 L30 40 H50 V60 C1 2 3 4 5 6 Q7 8 9 10 Z") == [
            .move(to: p(10, 20)), .line(to: p(30, 40)), .line(to: p(50, 40)), .line(to: p(50, 60)),
            .cubic(control1: p(1, 2), control2: p(3, 4), to: p(5, 6)), .quad(control: p(7, 8), to: p(9, 10)), .close,
        ])
        #expect(try path("m10 10 h5 v5 c1 1 2 2 3 3 q1 0 2 0 z l5 5") == [
            .move(to: p(10, 10)), .line(to: p(15, 10)), .line(to: p(15, 15)), .cubic(control1: p(16, 16), control2: p(17, 17), to: p(18, 18)),
            .quad(control: p(19, 18), to: p(20, 18)), .close, .line(to: p(15, 15)),
        ])
        #expect(try path("M0 0 1 1 L2 2 3 3") == [.move(to: p(0, 0)), .line(to: p(1, 1)), .line(to: p(2, 2)), .line(to: p(3, 3))])
        #expect(try path("m1 1 2 2") == [.move(to: p(1, 1)), .line(to: p(3, 3))])
        #expect(try path("M1.5.5L-1-2+3,4e1 .5E-1-.5") == [.move(to: p(1.5, 0.5)), .line(to: p(-1, -2)), .line(to: p(3, 40)), .line(to: p(0.05, -0.5))])
    }

    @Test(.disabled("waits on VI-4")) func relativeLine() throws {
        #expect(try path("M10 10 l5 5 l5 0") == [.move(to: p(10, 10)), .line(to: p(15, 15)), .line(to: p(20, 15))])
    }

    @Test(.disabled("waits on VI-4")) func smoothReflects() throws {
        #expect(try path("M0 0 C0 10 10 10 10 0 S20 -10 20 0") == [.move(to: p(0, 0)),
            .cubic(control1: p(0, 10), control2: p(10, 10), to: p(10, 0)), .cubic(control1: p(10, -10), control2: p(20, -10), to: p(20, 0))])
        #expect(try path("M0 0 Q5 10 10 0 T20 0") == [.move(to: p(0, 0)), .quad(control: p(5, 10), to: p(10, 0)), .quad(control: p(15, -10), to: p(20, 0))])
        #expect(try path("M0 0 L5 5 S10 0 20 0") == [.move(to: p(0, 0)), .line(to: p(5, 5)), .cubic(control1: p(5, 5), control2: p(10, 0), to: p(20, 0))])
    }

    /// True when the path is a move then cubics whose ends and t = 0.5 points lie within 1e-9 of the circle.
    func onCircle(_ elements: [PathElement], center c: Point, r: Double) -> Bool {
        guard case .move(var last)? = elements.first, elements.count > 1 else { return false }
        return elements.dropFirst().allSatisfy { e in
            guard case let .cubic(c1, c2, to) = e else { return false }
            let mid = p((last.x + 3 * c1.x + 3 * c2.x + to.x) / 8, (last.y + 3 * c1.y + 3 * c2.y + to.y) / 8)
            last = to
            return [mid, to].allSatisfy { abs(hypot($0.x - c.x, $0.y - c.y) - r) <= 1e-9 }
        }
    }

    @Test(.disabled("waits on VI-4")) func arcSweepFlag() throws {
        #expect(onCircle(try path("M10 0 A10 10 0 0 1 0 10"), center: p(0, 0), r: 10))
        #expect(onCircle(try path("M10 0 A10 10 0 0 0 0 10"), center: p(10, 10), r: 10))
        #expect(onCircle(try path("M10 0 a10 10 0 0 1 -10 10"), center: p(0, 0), r: 10))
        // One cubic per quarter turn; a zero radius is a line.
        #expect(try path("M10 0 A10 10 0 0 1 0 10").count == 2)
        let half = try path("M10 0 A10 10 0 0 1 -10 0")
        #expect(half.count == 3 && onCircle(half, center: p(0, 0), r: 10))
        #expect(try path("M0 0 A0 5 0 0 1 10 0") == [.move(to: p(0, 0)), .line(to: p(10, 0))])
    }

    @Test(.disabled("waits on VI-4")) func badTokenThrowsWithOffset() {
        guard case .damaged(let why)? = ImportFixture.error({ _ = try path("M 0 0 L 1 x") }) else { Issue.record("not damaged"); return }
        #expect(why.contains("10"))
        for d in ["M0 0 L", "L1 1", "M0 0 A1 1 0 2 1 5 5", "M0 0 L1e999 0"] {
            #expect(throws: ImportError.self, "\(d)") { _ = try path(d) }
        }
    }
}
