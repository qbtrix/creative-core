// LottieExporter.swift: a scene as a static Lottie JSON document.
//
// Follows the public Lottie format docs. The top level carries `v`, `fr`
// (fps), `ip`/`op` (frame range), `w`/`h` (canvas size) and `layers`. Each
// Flare layer becomes one shape layer (`ty` 4). Lottie draws the first layer
// on top, so the order is reversed (Flare draws its first layer first).
// Hidden layers are kept with `hd: true`.
//
// Each layer's scale, rotation and opacity are sampled at frame 0. When its x
// or y track has more than one keyframe, the position is written split
// (`p.s` true) with one animated property per axis: a keyframe has `t`, `s`,
// and either `h: 1` for hold or `o`/`i` tangents (linear is (0,0)/(1,1); a
// cubic Bezier gives (x1,y1)/(x2,y2) with x clamped to 0...1 as `Easing` does).
// Each shape becomes a group (`gr`) of its subpaths (`sh`), its fill (`fl`
// for a solid color, `gf` for a gradient) and an identity group transform
// (`tr`). A radial gradient's end point is its center moved right by the
// radius. Gradient stop alpha is not written; the fill is opaque. Bezier tangents are relative
// to their vertex; quads are raised to cubics. A non-finite value throws.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum LottieExportError: Error, Equatable, Sendable {
    case nonFiniteValue
}

public enum LottieExporter {
    /// The Lottie format version written in `v`.
    public static let version = "5.7.0"

    public static func export(scene: Scene) throws -> Data {
        let layers = try scene.layers.enumerated().reversed().map { index, layer in
            try LottieLayer(layer, index: index + 1, durationFrames: scene.durationFrames)
        }
        let root = LottieRoot(
            v: version, fr: scene.fps, ip: 0, op: scene.durationFrames,
            w: try finite(scene.width), h: try finite(scene.height), nm: scene.name,
            ddd: 0, assets: [], layers: layers
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(root)
    }

    static func finite(_ value: Double) throws -> Double {
        guard value.isFinite else { throw LottieExportError.nonFiniteValue }
        return value
    }

    /// One `sh` bezier per subpath of `path`. Empty subpaths are dropped.
    static func beziers(_ path: Path) throws -> [LottieBezier] {
        var result: [LottieBezier] = []
        var current = LottieBezier()
        var last = Point(x: 0, y: 0)
        var start = last
        func flush() {
            if !current.v.isEmpty { result.append(current) }
            current = LottieBezier()
        }
        func vertex(_ p: Point, inTangent: Point) throws {
            current.v.append([try finite(p.x), try finite(p.y)])
            current.i.append([try finite(inTangent.x - p.x), try finite(inTangent.y - p.y)])
            current.o.append([0, 0])
            last = p
        }
        func setOut(_ control: Point) throws {
            guard !current.o.isEmpty else { return }
            current.o[current.o.count - 1] = [try finite(control.x - last.x), try finite(control.y - last.y)]
        }
        for element in path.elements {
            switch element {
            case .move(let to):
                flush()
                start = to
                try vertex(to, inTangent: to)
            case .line(let to):
                if current.v.isEmpty { try vertex(last, inTangent: last) }
                try vertex(to, inTangent: to)
            case .quad(let c, let to):
                if current.v.isEmpty { try vertex(last, inTangent: last) }
                let c1 = Point(x: last.x + 2 * (c.x - last.x) / 3, y: last.y + 2 * (c.y - last.y) / 3)
                let c2 = Point(x: to.x + 2 * (c.x - to.x) / 3, y: to.y + 2 * (c.y - to.y) / 3)
                try setOut(c1)
                try vertex(to, inTangent: c2)
            case .cubic(let c1, let c2, let to):
                if current.v.isEmpty { try vertex(last, inTangent: last) }
                try setOut(c1)
                try vertex(to, inTangent: c2)
            case .close:
                current.c = true
                flush()
                last = start
            }
        }
        flush()
        return result
    }
}

/// A non-animated Lottie property: `{"a": 0, "k": value}`.
struct LottieStatic<Value: Encodable & Sendable>: Encodable, Sendable {
    var a = 0
    var k: Value
    init(_ k: Value) { self.k = k }
}

struct LottieRoot: Encodable, Sendable {
    var v: String
    var fr: Int
    var ip: Int
    var op: Int
    var w: Double
    var h: Double
    var nm: String
    var ddd: Int
    var assets: [Int]
    var layers: [LottieLayer]
}

struct LottieTransform: Encodable, Sendable {
    var a = LottieStatic([0.0, 0.0])
    var p: LottiePosition
    var s: LottieStatic<[Double]>
    var r: LottieStatic<Double>
    var o: LottieStatic<Double>
}

struct LottieLayer: Encodable, Sendable {
    var ddd = 0
    var ind: Int
    var ty = 4
    var nm: String
    var ip = 0
    var op: Int
    var st = 0
    var sr = 1
    var hd: Bool
    var ks: LottieTransform
    var shapes: [LottieGroup]

    init(_ layer: Layer, index: Int, durationFrames: Int) throws {
        let s = layer.sample(at: 0)
        func value(_ key: String, _ fallback: Double) throws -> Double {
            try LottieExporter.finite(s[key] ?? fallback)
        }
        ind = index
        nm = layer.name
        op = durationFrames
        hd = !layer.isVisible
        let xs = layer.tracks["x"] ?? []
        let ys = layer.tracks["y"] ?? []
        let position: LottiePosition
        if xs.count > 1 || ys.count > 1 {
            position = .split(x: try LottieScalar(xs, at0: try value("x", 0)),
                              y: try LottieScalar(ys, at0: try value("y", 0)))
        } else {
            position = .combined(LottieStatic([try value("x", 0), try value("y", 0)]))
        }
        ks = LottieTransform(
            p: position,
            s: LottieStatic([try value("scaleX", 1) * 100, try value("scaleY", 1) * 100]),
            r: LottieStatic(try value("rotation", 0)),
            o: LottieStatic(min(max(try value("opacity", 1), 0), 1) * 100)
        )
        shapes = try layer.shapes.map(LottieGroup.init)
    }
}

/// A layer position: one static point, or split into per-axis properties.
enum LottiePosition: Encodable, Sendable {
    case combined(LottieStatic<[Double]>)
    case split(x: LottieScalar, y: LottieScalar)

    private enum Keys: String, CodingKey { case s, x, y }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .combined(let point):
            try point.encode(to: encoder)
        case .split(let x, let y):
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(true, forKey: .s)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        }
    }
}

/// A scalar property: static (`a` 0) or animated (`a` 1) from a track.
enum LottieScalar: Encodable, Sendable {
    case fixed(LottieStatic<Double>)
    case animated([LottieKeyframe])

    /// `at0` is the track's value at frame 0, used when it has under two keyframes.
    init(_ track: [Keyframe], at0: Double) throws {
        guard track.count > 1 else {
            self = .fixed(LottieStatic(at0))
            return
        }
        var frames: [LottieKeyframe] = []
        for (index, keyframe) in track.enumerated() {
            var out = LottieKeyframe(t: keyframe.frame, s: [try LottieExporter.finite(keyframe.value)])
            if index < track.count - 1 {
                switch keyframe.easing {
                case .hold:
                    out.h = 1
                case .linear:
                    out.o = LottieEase(0, 0)
                    out.i = LottieEase(1, 1)
                case let .cubicBezier(x1, y1, x2, y2):
                    if x1.isFinite, y1.isFinite, x2.isFinite, y2.isFinite {
                        out.o = LottieEase(min(max(x1, 0), 1), y1)
                        out.i = LottieEase(min(max(x2, 0), 1), y2)
                    } else {
                        out.o = LottieEase(0, 0)
                        out.i = LottieEase(1, 1)
                    }
                }
            }
            frames.append(out)
        }
        self = .animated(frames)
    }

    private enum Keys: String, CodingKey { case a, k }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .fixed(let value):
            try value.encode(to: encoder)
        case .animated(let frames):
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(1, forKey: .a)
            try container.encode(frames, forKey: .k)
        }
    }
}

/// One keyframe of an animated property. The last one carries only `t` and `s`.
struct LottieKeyframe: Encodable, Sendable {
    var t: Int
    var s: [Double]
    var o: LottieEase?
    var i: LottieEase?
    var h: Int?
}

/// An easing tangent: `{"x": [x], "y": [y]}` on the 0...1 progress square.
struct LottieEase: Encodable, Sendable {
    var x: [Double]
    var y: [Double]
    init(_ x: Double, _ y: Double) {
        self.x = [x]
        self.y = [y]
    }
}

/// A shape item. Fields not used by an item's `ty` are left out.
struct LottieItem: Encodable, Sendable {
    var ty: String
    var ks: LottieStatic<LottieBezier>?
    var c: LottieStatic<[Double]>?
    var o: LottieStatic<Double>?
    /// The fill rule on `fl` (1 is non-zero), the rotation on `tr`.
    var r: LottieR?
    var p: LottieStatic<[Double]>?
    var a: LottieStatic<[Double]>?
    var s: LottieStatic<[Double]>?
    /// Gradient type on `gf`: 1 linear, 2 radial.
    var t: Int?
    var e: LottieStatic<[Double]>?
    var g: LottieGradientStops?

    init(ty: String) { self.ty = ty }
}

/// Gradient stops: `p` stops, flattened as offset, r, g, b for each.
struct LottieGradientStops: Encodable, Sendable {
    var p: Int
    var k: LottieStatic<[Double]>
}

enum LottieR: Encodable, Sendable {
    case rule(Int)
    case rotation(LottieStatic<Double>)

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .rule(let rule): try container.encode(rule)
        case .rotation(let rotation): try container.encode(rotation)
        }
    }
}

struct LottieGroup: Encodable, Sendable {
    var ty = "gr"
    var it: [LottieItem]

    init(_ shape: Shape) throws {
        var items = try LottieExporter.beziers(shape.outline).map { bezier in
            var item = LottieItem(ty: "sh")
            item.ks = LottieStatic(bezier)
            return item
        }
        func channel(_ v: Double) throws -> Double { min(max(try LottieExporter.finite(v), 0), 1) }
        func gradient(_ stops: [GradientStop]) throws -> LottieGradientStops {
            let flat = try stops.flatMap { stop in
                [try channel(stop.offset), try channel(stop.color.r),
                 try channel(stop.color.g), try channel(stop.color.b)]
            }
            return LottieGradientStops(p: stops.count, k: LottieStatic(flat))
        }
        func point(_ p: Point) throws -> LottieStatic<[Double]> {
            LottieStatic([try LottieExporter.finite(p.x), try LottieExporter.finite(p.y)])
        }
        var fill = LottieItem(ty: "gf")
        switch shape.fill {
        case .solid(let color):
            fill = LottieItem(ty: "fl")
            fill.c = LottieStatic([try channel(color.r), try channel(color.g), try channel(color.b), 1])
            fill.o = LottieStatic(try channel(color.a) * 100)
        case .linear(let stops, let start, let end):
            fill.t = 1
            fill.s = try point(start)
            fill.e = try point(end)
            fill.g = try gradient(stops)
        case .radial(let stops, let center, let radius):
            fill.t = 2
            fill.s = try point(center)
            fill.e = try point(Point(x: center.x + radius, y: center.y))
            fill.g = try gradient(stops)
        }
        if fill.ty == "gf" { fill.o = LottieStatic(100) }
        fill.r = .rule(1)
        var transform = LottieItem(ty: "tr")
        transform.p = LottieStatic([0, 0])
        transform.a = LottieStatic([0, 0])
        transform.s = LottieStatic([100, 100])
        transform.r = .rotation(LottieStatic(0))
        transform.o = LottieStatic(100)
        items += [fill, transform]
        it = items
    }
}

/// Lottie bezier data: vertices with in and out tangents relative to them.
struct LottieBezier: Encodable, Sendable {
    var c = false
    var v: [[Double]] = []
    var i: [[Double]] = []
    var o: [[Double]] = []
}
