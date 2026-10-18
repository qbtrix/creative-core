// LottieExporter.swift: a scene as a static or animated Lottie JSON document.
//
// Follows the public Lottie format docs. The top level carries `v`, `fr`
// (fps), `ip`/`op` (frame range), `w`/`h` (canvas size) and `layers`. Each
// Flare layer becomes one shape layer (`ty` 4). Lottie draws the first layer
// on top, so the order is reversed (Flare draws its first layer first).
// Hidden layers are kept with `hd: true`.
//
// When a layer's x or y track has more than one keyframe, the position is
// written split (`p.s` true) with one animated property per axis; a rotation
// or opacity track with more than one keyframe animates `ks.r` (degrees) or
// `ks.o` (clamped to 0...1, times 100) the same way, and with fewer it is its
// frame-0 value. Scale (`ks.s`, times 100) is one 2-D property: static when
// neither scale track has two keyframes; the keyed track's keyframes with the
// other axis constant when only one has; shared keyframes when both have keys
// at the same frames with the same easings; otherwise one linear keyframe per
// frame, sampled, from the first key to the last within the scene, capped at
// `maxBakedKeys`. A keyframe has `t`, `s`, and either `h: 1` for hold or
// `o`/`i` tangents (linear is (0,0)/(1,1); a cubic Bezier gives (x1,y1)/(x2,y2)
// with x clamped to 0...1 as `Easing` does).
//
// Each shape becomes a group (`gr`) of its subpaths (`sh`), its stroke (`st`)
// if any, its fill (`fl` for a solid color, `gf` for a gradient) and an
// identity group transform (`tr`). Each instance becomes a group, above the
// layer's shapes, holding one group per visible symbol layer sampled at the
// symbol frame (`Instance.resolve`), each with its own `tr`. A radial
// gradient's end point is its center moved right by the radius. A gradient's
// stop alpha is written as `[offset, alpha]` for each stop after the color
// stops, only when some stop alpha is under 1; `p` stays the color stop count.
// Bezier tangents are relative to their vertex; quads are raised to cubics.
// A non-finite value, including one that overflows when scaled, throws.
// Text is not written yet: a layer with text throws `unsupported("text")`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum LottieExportError: Error, Equatable, Sendable {
    case nonFiniteValue
    /// An instance names a symbol that is missing, contains itself, or is
    /// nested deeper than `Instance.maxNestingDepth`.
    case unresolvedSymbol(String)
    /// The scene draws something this exporter cannot write yet, e.g. "text".
    case unsupported(String)
}

public enum LottieExporter {
    /// The Lottie format version written in `v`.
    public static let version = "5.7.0"

    /// The most keyframes a baked scale property may hold. Scale tracks keyed
    /// at different frames are baked one keyframe per frame; past this many the
    /// export throws `unsupported("scale track")` instead of writing a huge file
    /// or allocating for a key range read from an untrusted document.
    public static let maxBakedKeys = 10_000

    /// `symbols` are the document's symbols, which the scene's instances name.
    public static func export(scene: Scene, symbols: [Symbol] = []) throws -> Data {
        let layers = try scene.layers.enumerated().reversed().map { index, layer in
            try LottieLayer(layer, index: index + 1, durationFrames: scene.durationFrames, symbols: symbols)
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

    /// A layer's shape items at `frame`: one group per instance, holding the
    /// symbol's visible layers, on top of one group per shape. `path` is the
    /// ids of the symbols being drawn around the layer.
    static func content(of layer: Layer, frame: Double, symbols: [Symbol], path: [String]) throws -> [LottieItem] {
        guard layer.texts.isEmpty else { throw LottieExportError.unsupported("text") }
        let instances = try layer.instances.reversed().map { instance in
            guard let (symbol, local) = instance.resolve(in: symbols, frame: frame, path: path) else {
                throw LottieExportError.unresolvedSymbol(instance.symbolID)
            }
            let layers = try symbol.layers.reversed().filter(\.isVisible).map { inner in
                let (transform, opacity) = inner.placement(at: local)
                let items = try content(of: inner, frame: local, symbols: symbols, path: path + [symbol.id])
                return group(items + [try LottieItem.transform(transform, opacity: opacity)])
            }
            return group(layers + [try LottieItem.transform(instance.transform, opacity: 1)])
        }
        return try instances + layer.shapes.enumerated().map { try LottieItem(shape: $1, index: $0, of: layer, frame: frame, animate: path.isEmpty) }
    }

    static func group(_ items: [LottieItem]) -> LottieItem {
        var group = LottieItem(ty: "gr")
        group.it = items
        return group
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
    var s: LottieProperty<[Double]>
    var r: LottieScalar
    var o: LottieScalar
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
    var shapes: [LottieItem]

    init(_ layer: Layer, index: Int, durationFrames: Int, symbols: [Symbol]) throws {
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
            s: try LottieProperty(scaleOf: layer, x0: try value("scaleX", 1), y0: try value("scaleY", 1),
                                  durationFrames: durationFrames),
            r: try LottieScalar(layer.tracks["rotation"] ?? [], at0: try value("rotation", 0)),
            o: try LottieScalar(layer.tracks["opacity"] ?? [], at0: try value("opacity", 1),
                                map: { min(max($0, 0), 1) * 100 })
        )
        shapes = try LottieExporter.content(of: layer, frame: 0, symbols: symbols, path: [])
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

/// A property: static (`a` 0) or animated (`a` 1) from keyframes.
enum LottieProperty<Value: Encodable & Sendable>: Encodable, Sendable {
    case fixed(LottieStatic<Value>)
    case animated([LottieKeyframe])

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

/// A shape item. Fields not used by an item's `ty` are left out.
struct LottieItem: Encodable, Sendable {
    var ty: String
    var ks: LottieProperty<LottieBezier>?
    var c: LottieProperty<[Double]>?
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
    /// Stroke width, line cap and line join on `st`.
    var w: LottieScalar?
    var lc: Int?
    var lj: Int?
    /// The items of a `gr` group, the first drawn on top.
    var it: [LottieItem]?

    init(ty: String) { self.ty = ty }

    /// A group transform (`tr`) placing the group's items.
    static func transform(_ t: Transform, opacity: Double) throws -> LottieItem {
        func f(_ v: Double) throws -> Double { try LottieExporter.finite(v) }
        var item = LottieItem(ty: "tr")
        item.p = LottieStatic([try f(t.x), try f(t.y)])
        item.a = LottieStatic([0, 0])
        item.s = LottieStatic([try f(t.scaleX * 100), try f(t.scaleY * 100)])
        item.r = .rotation(LottieStatic(try f(t.rotation)))
        item.o = LottieStatic(min(max(try f(opacity), 0), 1) * 100)
        return item
    }
}

/// Gradient stops: `p` stops, flattened as offset, r, g, b for each, then, only
/// when some stop alpha is under 1, offset, alpha for each.
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

extension LottieItem {
    /// A group of the shape's subpaths, its stroke, its fill and an identity transform.
    init(shape: Shape) throws {
        var items = try LottieExporter.beziers(shape.outline).map { bezier in
            var item = LottieItem(ty: "sh")
            item.ks = .fixed(LottieStatic(bezier))
            return item
        }
        func channel(_ v: Double) throws -> Double { try LottieExporter.unit(v) }
        func gradient(_ stops: [GradientStop]) throws -> LottieGradientStops {
            let alphas = try stops.map { try channel($0.color.a) }
            var flat = try stops.flatMap { stop in
                [try channel(stop.offset), try channel(stop.color.r),
                 try channel(stop.color.g), try channel(stop.color.b)]
            }
            if alphas.contains(where: { $0 < 1 }) {
                for (stop, alpha) in zip(stops, alphas) {
                    flat += [try channel(stop.offset), alpha]
                }
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
            fill.c = .fixed(LottieStatic([try channel(color.r), try channel(color.g), try channel(color.b), 1]))
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
        if let stroke = shape.stroke {
            var item = LottieItem(ty: "st")
            item.c = .fixed(LottieStatic([try channel(stroke.color.r), try channel(stroke.color.g),
                                          try channel(stroke.color.b), 1]))
            item.o = LottieStatic(try channel(stroke.color.a) * 100)
            item.w = .fixed(LottieStatic(try LottieExporter.finite(stroke.width)))
            item.lc = [.butt: 1, .round: 2, .square: 3][stroke.cap]
            item.lj = [.miter: 1, .round: 2, .bevel: 3][stroke.join]
            items.append(item)
        }
        items += [fill, try LottieItem.transform(.identity, opacity: 1)]
        self = LottieExporter.group(items)
    }
}

/// Lottie bezier data: vertices with in and out tangents relative to them.
struct LottieBezier: Encodable, Sendable {
    var c = false
    var v: [[Double]] = []
    var i: [[Double]] = []
    var o: [[Double]] = []
}
