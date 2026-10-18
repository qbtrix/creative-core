import Foundation
import Testing
@testable import FlareCore

/// SVG path data to `Path` (VI-4): every command, implicit repeats, the number grammar and arcs as cubics.
struct SVGPathDataTests {
    func path(_ d: String) throws -> [PathElement] { try SVGPathData.path(d).elements }
    func p(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }

    @Test func commandsRepeatsAndNumbers() throws {
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

    @Test func relativeLine() throws {
        #expect(try path("M10 10 l5 5 l5 0") == [.move(to: p(10, 10)), .line(to: p(15, 15)), .line(to: p(20, 15))])
    }

    @Test func smoothReflects() throws {
        #expect(try path("M0 0 C0 10 10 10 10 0 S20 -10 20 0") == [.move(to: p(0, 0)),
            .cubic(control1: p(0, 10), control2: p(10, 10), to: p(10, 0)), .cubic(control1: p(10, -10), control2: p(20, -10), to: p(20, 0))])
        #expect(try path("M0 0 Q5 10 10 0 T20 0") == [.move(to: p(0, 0)), .quad(control: p(5, 10), to: p(10, 0)), .quad(control: p(15, -10), to: p(20, 0))])
        #expect(try path("M0 0 L5 5 S10 0 20 0") == [.move(to: p(0, 0)), .line(to: p(5, 5)), .cubic(control1: p(5, 5), control2: p(10, 0), to: p(20, 0))])
    }

    /// True when the path is a move then cubics whose ends and t = 0.5 points lie within about 1e-9 of the circle,
    /// the last ending exactly at `end`.
    func onCircle(_ elements: [PathElement], center c: Point, r: Double, end: Point) -> Bool {
        guard case .cubic(_, _, let last)? = elements.last, last == end else { return false }
        return onEllipse(elements, center: c, rx: r, ry: r, degrees: 0, within: 2e-9 / r)
    }

    /// True when the path is a move then cubics whose ends and t = 0.5 points, rotated by -`degrees` about
    /// `c`, satisfy (x/rx)^2 + (y/ry)^2 = 1 within `within`.
    func onEllipse(_ elements: [PathElement], center c: Point, rx: Double, ry: Double, degrees: Double, within: Double) -> Bool {
        guard case .move(var last)? = elements.first, elements.count > 1 else { return false }
        let (cs, sn) = (cos(degrees * .pi / 180), sin(degrees * .pi / 180))
        return elements.dropFirst().allSatisfy { e in
            guard case let .cubic(c1, c2, to) = e else { return false }
            let mid = p((last.x + 3 * c1.x + 3 * c2.x + to.x) / 8, (last.y + 3 * c1.y + 3 * c2.y + to.y) / 8)
            last = to
            return [mid, to].allSatisfy { q in
                let (dx, dy) = (q.x - c.x, q.y - c.y)
                let (x, y) = ((cs * dx + sn * dy) / rx, (-sn * dx + cs * dy) / ry)
                return abs(x * x + y * y - 1) <= within
            }
        }
    }

    /// The arc's centre and radii, solved here by W3C SVG implementation notes F.6.5 and F.6.6.
    func arcCentre(from a: Point, to b: Point, rx: Double, ry: Double, degrees: Double, largeArc: Bool, sweep: Bool) -> (Point, Double, Double) {
        let (cs, sn) = (cos(degrees * .pi / 180), sin(degrees * .pi / 180))
        let (hx, hy) = ((a.x - b.x) / 2, (a.y - b.y) / 2)
        let (x1, y1) = (cs * hx + sn * hy, -sn * hx + cs * hy)
        let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        let (rx, ry) = lambda > 1 ? (rx * lambda.squareRoot(), ry * lambda.squareRoot()) : (rx, ry)
        let radicand = (rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1) / (rx * rx * y1 * y1 + ry * ry * x1 * x1)
        let k = (largeArc != sweep ? 1.0 : -1.0) * Swift.max(0, radicand).squareRoot()
        let (cx1, cy1) = (k * rx * y1 / ry, -k * ry * x1 / rx)
        return (p(cs * cx1 - sn * cy1 + (a.x + b.x) / 2, sn * cx1 + cs * cy1 + (a.y + b.y) / 2), rx, ry)
    }

    @Test func ellipticalArcOnEllipse() throws {
        // Radii that reach the chord, then radii too small (lambda > 1) that scale up.
        for (d, rx, ry, scaled) in [("M0 0 A40 20 30 0 1 50 25", 40.0, 20.0, false), ("M0 0 A4 2 30 0 1 50 25", 4.0, 2.0, true)] {
            let (c, sx, sy) = arcCentre(from: p(0, 0), to: p(50, 25), rx: rx, ry: ry, degrees: 30, largeArc: false, sweep: true)
            let arc = try path(d)
            #expect((sx > rx) == scaled, "\(d) scales up only when lambda > 1")
            #expect(onEllipse(arc, center: c, rx: sx, ry: sy, degrees: 30, within: 1e-3), "\(d)")
            guard case .cubic(_, _, p(50, 25))? = arc.last else { Issue.record("\(d) ends elsewhere"); continue }
        }
    }

    @Test func arcSweepFlag() throws {
        #expect(onCircle(try path("M10 0 A10 10 0 0 1 0 10"), center: p(0, 0), r: 10, end: p(0, 10)))
        #expect(onCircle(try path("M10 0 A10 10 0 0 0 0 10"), center: p(10, 10), r: 10, end: p(0, 10)))
        #expect(onCircle(try path("M10 0 a10 10 0 0 1 -10 10"), center: p(0, 0), r: 10, end: p(0, 10)))
        // One cubic per quarter turn; a zero radius is a line.
        #expect(try path("M10 0 A10 10 0 0 1 0 10").count == 2)
        let half = try path("M10 0 A10 10 0 0 1 -10 0")
        #expect(half.count == 3 && onCircle(half, center: p(0, 0), r: 10, end: p(-10, 0)))
        #expect(try path("M0 0 A0 5 0 0 1 10 0") == [.move(to: p(0, 0)), .line(to: p(10, 0))])
    }

    @Test func badTokenThrowsWithOffset() {
        guard case .damaged(let why)? = ImportFixture.error({ _ = try path("M 0 0 L 1 x") }) else { Issue.record("not damaged"); return }
        #expect(why.contains("at byte 10"))
        for d in ["M0 0 L", "L1 1", "M0 0 A1 1 0 2 1 5 5", "M0 0 L1e999 0"] {
            #expect(throws: ImportError.self, "\(d)") { _ = try path(d) }
        }
    }

    @Test func largeArcFlag() throws {
        // 270 degrees the long way round: three quarter cubics.
        let large = try path("M10 0 A10 10 0 1 1 0 10")
        #expect(large.count == 4 && onCircle(large, center: p(10, 10), r: 10, end: p(0, 10)))
    }

    @Test func arcRadiiAndRotation() throws {
        // F.6.6: radii too small for the chord scale up to a half circle on its midpoint.
        let scaled = try path("M0 0 A1 1 0 0 1 10 0")
        #expect(scaled.count == 3 && onCircle(scaled, center: p(5, 0), r: 5, end: p(10, 0)))
        // An x-axis rotation of 90 degrees swaps the radii.
        let rotated = try path("M0 0 A10 5 90 0 1 0 20"), swapped = try path("M0 0 A5 10 0 0 1 0 20")
        #expect(rotated.count == swapped.count && zip(rotated, swapped).allSatisfy { a, b in
            zip(a.points, b.points).allSatisfy { abs($0.x - $1.x) <= 1e-9 && abs($0.y - $1.y) <= 1e-9 }
        })
        #expect(try path("M5 5 A3 4 0 0 1 5 5") == [.move(to: p(5, 5))])
        #expect(try path(" ") == [])
    }

    @Test func boundsThrow() {
        #expect(throws: ImportError.tooLarge("path data over \(SVGPathData.maxBytes) bytes")) {
            _ = try SVGPathData.path(String(repeating: " ", count: SVGPathData.maxBytes + 1))
        }
        #expect(throws: ImportError.self) { _ = try path("M1e308 0 l1e308 0") }
        #expect(throws: ImportError.self) { _ = try path("M0 0 Z 1 1") }
    }

    static let extremeArcs = ["M0 0 A1 1 0 0 1 1e-200 0", "M0 0 A1 1 0 0 1 5e-324 0", "M0 0 A1 1 0 0 1 1e200 0"]

    /// Chords so short or long that the centre is inf or NaN throw instead of trapping on the segment count.
    @Test func extremeArcChordsThrow() throws {
        for d in Self.extremeArcs {
            guard case .damaged(let why)? = ImportFixture.error({ _ = try path(d) }) else { Issue.record("\(d) not damaged"); continue }
            #expect(why.contains("arc centre out of range"), "\(d): \(why)")
        }
        // Large but finite throughout: a half circle of radius 5e69 on its midpoint.
        let big = try path("M0 0 A5e69 5e69 0 0 1 1e70 0")
        #expect(big.count == 3 && big.allSatisfy { $0.points.allSatisfy(\.isFinite) })
        guard case .cubic(_, _, p(1e70, 0))? = big.last else { Issue.record("big arc ends elsewhere"); return }
    }

    /// Random strings over the path alphabet after each seed parse or throw `ImportError` in under 1 s; they never crash.
    @Test func fuzzThrowsInsteadOfCrashing() {
        var rng = SplitMix64(seed: 0x5E6_DA7A)
        let alphabet = Array("MmLlHhVvCcSsQqTtAaZz0123456789.-+eE ,x\t")
        let seeds = ["M0 0"] + Self.extremeArcs + ["M0 0 A5e69 5e69 0 0 1 1e70 0"]
        for i in 0..<2_000 {
            let length = Int.random(in: 1...40, using: &rng)
            let d = seeds[i % seeds.count] + String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
            let took = ContinuousClock().measure {
                do { _ = try SVGPathData.path(d) } catch is ImportError {} catch { Issue.record("\(d): \(error)") }
            }
            #expect(took < .seconds(1), "\(d) took \(took)")
        }
    }
}
