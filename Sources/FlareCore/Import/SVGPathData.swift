// SVGPathData.swift: SVG path data (the `d` attribute) read into a `Path`.
//
// Follows the path grammar of W3C SVG 1.1 and SVG 2: commands M L H V C S Q T
// A Z, upper case absolute and lower case relative to the current point; a
// command letter may be left out to repeat the last command (after M, m the
// repeats are L, l); numbers take a sign, decimals and exponents and need no
// separator where the next one cannot continue them ("1.5.5" is 1.5 and 0.5,
// "-1-2" is -1 and -2); arc flags are one character each.
//
// Invariants:
// - S and T reflect the previous C/S or Q/T control point about the current
//   point, else the control point is the current point
// - an arc becomes one cubic per <= 90 degrees of sweep by the W3C
//   endpoint-to-centre conversion (implementation notes F.6.5), radii scaled up
//   when too small (F.6.6), zero radius gives a line, zero length gives nothing;
//   a chord so short or long that the centre or sweep is not finite throws
// - a bad token, a missing argument or a non-finite number or point throws
//   `ImportError.damaged` saying "at byte N", N the 0-based UTF-8 offset; input over `maxBytes` or
//   output over `maxElements` throws `ImportError.tooLarge`
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Reads SVG path data into a `Path`. Throws `ImportError`.
public enum SVGPathData {
    /// The longest path data read, in bytes: a whole SVG document's cap.
    public static let maxBytes = SVGImport.maxBytes
    /// The most path elements one path data string may produce.
    public static let maxElements = 1 << 20

    /// The path that `d` draws. Empty or all-whitespace data is an empty path.
    public static func path(_ d: String) throws -> Path {
        guard d.utf8.count <= maxBytes else { throw ImportError.tooLarge("path data over \(maxBytes) bytes") }
        var reader = PathDataReader(bytes: Array(d.utf8))
        return Path(elements: try reader.read())
    }
}

private struct PathDataReader {
    let bytes: [UInt8]
    var at = 0
    var elements: [PathElement] = []
    var current = Point(x: 0, y: 0)
    var subpathStart = Point(x: 0, y: 0)
    /// The second control point of the last element when it was C or S.
    var lastCubic: Point?
    /// The control point of the last element when it was Q or T.
    var lastQuad: Point?

    init(bytes: [UInt8]) { self.bytes = bytes }

    var peek: UInt8? { at < bytes.count ? bytes[at] : nil }

    func damaged(_ what: String) -> ImportError { .damaged("path data: \(what) at byte \(at)") }

    mutating func skipSeparators() {
        while let c = peek, c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C || c == UInt8(ascii: ",") {
            at += 1
        }
    }

    var atNumber: Bool {
        guard let c = peek else { return false }
        return isDigit(c) || c == UInt8(ascii: ".") || c == UInt8(ascii: "-") || c == UInt8(ascii: "+")
    }

    mutating func read() throws -> [PathElement] {
        skipSeparators()
        var command: UInt8?
        while let c = peek {
            if isLetter(c) {
                at += 1
                command = c
            } else if command == nil || command == UInt8(ascii: "z") || command == UInt8(ascii: "Z") || !atNumber {
                throw damaged("unexpected character")
            }
            guard let letter = command else { throw damaged("missing command") }
            if elements.isEmpty, letter != UInt8(ascii: "M"), letter != UInt8(ascii: "m") {
                throw damaged("path data must start with a move")
            }
            let before = elements.count
            try apply(letter)
            guard elements.dropFirst(before).allSatisfy({ $0.points.allSatisfy(\.isFinite) }) else {
                throw damaged("coordinate out of range")
            }
            // A repeated move draws lines.
            if letter == UInt8(ascii: "M") { command = UInt8(ascii: "L") }
            if letter == UInt8(ascii: "m") { command = UInt8(ascii: "l") }
            guard elements.count <= SVGPathData.maxElements else {
                throw ImportError.tooLarge("path data over \(SVGPathData.maxElements) elements")
            }
            skipSeparators()
        }
        return elements
    }

    mutating func apply(_ letter: UInt8) throws {
        let relative = letter >= UInt8(ascii: "a")
        let base = relative ? current : Point(x: 0, y: 0)
        var cubic: Point?
        var quad: Point?
        switch letter | 0x20 {
        case UInt8(ascii: "m"):
            let to = try point(base)
            elements.append(.move(to: to))
            subpathStart = to
            current = to
        case UInt8(ascii: "l"):
            current = try point(base)
            elements.append(.line(to: current))
        case UInt8(ascii: "h"):
            current = Point(x: try number() + base.x, y: current.y)
            elements.append(.line(to: current))
        case UInt8(ascii: "v"):
            current = Point(x: current.x, y: try number() + base.y)
            elements.append(.line(to: current))
        case UInt8(ascii: "c"), UInt8(ascii: "s"):
            let c1 = letter | 0x20 == UInt8(ascii: "c") ? try point(base) : reflect(lastCubic)
            let c2 = try point(base)
            current = try point(base)
            elements.append(.cubic(control1: c1, control2: c2, to: current))
            cubic = c2
        case UInt8(ascii: "q"), UInt8(ascii: "t"):
            let c = letter | 0x20 == UInt8(ascii: "q") ? try point(base) : reflect(lastQuad)
            current = try point(base)
            elements.append(.quad(control: c, to: current))
            quad = c
        case UInt8(ascii: "a"):
            let rx = abs(try number()), ry = abs(try number()), phi = try number()
            let largeArc = try flag(), sweep = try flag()
            let to = try point(base)
            try appendArc(to: to, rx: rx, ry: ry, degrees: phi, largeArc: largeArc, sweep: sweep)
        case UInt8(ascii: "z"):
            elements.append(.close)
            current = subpathStart
        default:
            at -= 1
            throw damaged("unknown command")
        }
        lastCubic = cubic
        lastQuad = quad
    }

    /// `control` reflected about the current point; the current point when nil.
    func reflect(_ control: Point?) -> Point {
        guard let c = control else { return current }
        return Point(x: 2 * current.x - c.x, y: 2 * current.y - c.y)
    }

    mutating func point(_ base: Point) throws -> Point {
        let x = try number()
        let y = try number()
        return Point(x: x + base.x, y: y + base.y)
    }

    mutating func flag() throws -> Bool {
        skipSeparators()
        switch peek {
        case UInt8(ascii: "0"): at += 1; return false
        case UInt8(ascii: "1"): at += 1; return true
        default: throw damaged("expected an arc flag")
        }
    }

    /// One number by the SVG grammar: sign? (digits ('.' digits?)? | '.' digits) exponent?
    mutating func number() throws -> Double {
        skipSeparators()
        let start = at
        if peek == UInt8(ascii: "-") || peek == UInt8(ascii: "+") { at += 1 }
        let intDigits = digits()
        var fracDigits = 0
        if peek == UInt8(ascii: ".") {
            at += 1
            fracDigits = digits()
        }
        guard intDigits + fracDigits > 0 else {
            at = start
            throw damaged("expected a number")
        }
        if peek == UInt8(ascii: "e") || peek == UInt8(ascii: "E") {
            at += 1
            if peek == UInt8(ascii: "-") || peek == UInt8(ascii: "+") { at += 1 }
            guard digits() > 0 else { throw damaged("expected exponent digits") }
        }
        let text = String(decoding: bytes[start..<at], as: UTF8.self)
        guard let value = Double(text), value.isFinite else {
            at = start
            throw damaged("number out of range")
        }
        return value
    }

    mutating func digits() -> Int {
        let start = at
        while let c = peek, isDigit(c) { at += 1 }
        return at - start
    }

    /// The SVG elliptical arc from the current point to `to` as cubics.
    mutating func appendArc(to: Point, rx: Double, ry: Double, degrees: Double, largeArc: Bool, sweep: Bool) throws {
        let from = current
        current = to
        guard from != to else { return }
        guard rx > 0, ry > 0 else {
            elements.append(.line(to: to))
            return
        }
        // F.6.5 step 1: the midpoint difference in the ellipse's own axes.
        let toAxes = Matrix.rotation(degrees: -degrees)
        let p = toAxes.apply(Point(x: (from.x - to.x) / 2, y: (from.y - to.y) / 2))
        // F.6.6: scale radii up until the ellipse reaches both ends.
        let lambda = (p.x * p.x) / (rx * rx) + (p.y * p.y) / (ry * ry)
        let scale = lambda > 1 ? lambda.squareRoot() : 1
        let (rx, ry) = (rx * scale, ry * scale)
        // Step 2: the centre in the ellipse's axes, on the side the flags pick.
        let num = rx * rx * ry * ry - rx * rx * p.y * p.y - ry * ry * p.x * p.x
        let den = rx * rx * p.y * p.y + ry * ry * p.x * p.x
        let sign: Double = largeArc != sweep ? 1 : -1
        let coef = sign * Swift.max(0, num / den).squareRoot()
        let centre = Point(x: coef * rx * p.y / ry, y: -coef * ry * p.x / rx)
        // Step 4: start angle and sweep on the unit circle.
        let start = atan2((p.y - centre.y) / ry, (p.x - centre.x) / rx)
        let end = atan2((-p.y - centre.y) / ry, (-p.x - centre.x) / rx)
        var delta = end - start
        if !sweep, delta > 0 { delta -= 2 * Double.pi }
        if sweep, delta < 0 { delta += 2 * Double.pi }
        // A chord near 1e-320 or 1e200 under- or overflows the centre to inf or NaN.
        guard [delta, centre.x, centre.y, rx, ry].allSatisfy(\.isFinite) else { throw damaged("arc centre out of range") }
        // Step 3: unit circle to user space.
        let mid = Point(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let toUser = Matrix.translation(x: mid.x, y: mid.y) * Matrix.rotation(degrees: degrees)
            * Matrix.translation(x: centre.x, y: centre.y) * Matrix.scale(x: rx, y: ry)
        let quarters = Swift.min(4, Swift.max(1, (abs(delta) / (Double.pi / 2) - 1e-9).rounded(.up)))
        let count = Int(exactly: quarters) ?? 1
        let step = delta / Double(count)
        let handle = 4.0 / 3.0 * tan(step / 4)
        for i in 0..<count {
            let a = start + step * Double(i)
            let b = a + step
            let c1 = Point(x: cos(a) - handle * sin(a), y: sin(a) + handle * cos(a))
            let c2 = Point(x: cos(b) + handle * sin(b), y: sin(b) - handle * cos(b))
            let end = i == count - 1 ? to : toUser.apply(Point(x: cos(b), y: sin(b)))
            elements.append(.cubic(control1: toUser.apply(c1), control2: toUser.apply(c2), to: end))
        }
    }
}

private func isDigit(_ c: UInt8) -> Bool { c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") }

private func isLetter(_ c: UInt8) -> Bool { (c | 0x20) >= UInt8(ascii: "a") && (c | 0x20) <= UInt8(ascii: "z") }
