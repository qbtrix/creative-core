// LottieExporter.swift: a scene as a static Lottie JSON document.
//
// Follows the public Lottie format docs. The top level carries `v`, `fr`
// (fps), `ip`/`op` (frame range), `w`/`h` (canvas size) and `layers`. Each
// Flare layer becomes one shape layer (`ty` 4). Lottie draws the first layer
// on top, so the order is reversed (Flare draws its first layer first).
// Hidden layers are kept with `hd: true`.
//
// Static subset: each layer's transform and opacity are sampled at frame 0.
// Each shape becomes a group (`gr`) of its subpaths (`sh`), a solid fill
// (`fl`) and an identity group transform (`tr`). Bezier tangents are relative
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
    var p: LottieStatic<[Double]>
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
        ks = LottieTransform(
            p: LottieStatic([try value("x", 0), try value("y", 0)]),
            s: LottieStatic([try value("scaleX", 1) * 100, try value("scaleY", 1) * 100]),
            r: LottieStatic(try value("rotation", 0)),
            o: LottieStatic(min(max(try value("opacity", 1), 0), 1) * 100)
        )
        shapes = try layer.shapes.map(LottieGroup.init)
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

    init(ty: String) { self.ty = ty }
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
        let color = shape.fill
        func channel(_ v: Double) throws -> Double { min(max(try LottieExporter.finite(v), 0), 1) }
        var fill = LottieItem(ty: "fl")
        fill.c = LottieStatic([try channel(color.r), try channel(color.g), try channel(color.b), 1])
        fill.o = LottieStatic(try channel(color.a) * 100)
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
