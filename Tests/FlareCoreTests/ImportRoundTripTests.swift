// ImportRoundTripTests.swift: KJ-VI, the vector-import walk. Every export
// fixture goes out through SVGExporter and LottieExporter and comes back in
// through SVGImport and LottieImport as it went out. SVG: layers in order after
// the background rect, flattened points within 1e-6 of the outline as written
// (4 decimals, transforms baked in), fills equal to the 8-bit paint. Lottie:
// layers in order, every track sampled at 20 frames within 1e-9. A hand-written
// SVG with an arc, a skewed group, a radial gradient and a `<filter>` reads with
// the filter skipped. Masks and mattes are left out: the exporters write
// neither yet (LottieExporter+Masks.swift is a stub), so no fixture has one.
@testable import FlareCore
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct ImportRoundTripTests {
    static let flatten = 0.25
    static let svgFrame = 75.0
    static let sampleCount = 20

    /// Every export fixture: the shared fixture, one with an instance, the
    /// keyed-tracks file, a layer of three differently keyed shapes, and the
    /// seeded `reference` scene.
    static func fixtures() throws -> [(name: String, document: Document)] {
        var instanced = Fixtures.withSymbol()
        instanced.symbols[0].layers[0].shapes = [Shape(points: [Point(x: 0, y: 0), Point(x: 6, y: 2), Point(x: 3, y: 7)])]
        instanced.scenes[0].layers[1].instances = [Instance(symbolID: "sym", transform: Transform(x: 30, y: 12, scaleX: 2, rotation: 30))]
        return [
            ("document", Fixtures.document()),
            ("instance", instanced),
            ("tracks", try TrackCommandsTests.fixture()),
            ("order", Document(scenes: [ordered()])),
            ("reference", try FlareBudgetTests.document(seed: 2026)),
        ]
    }

    /// Three shapes of different colours on one layer, the first and last with
    /// fill tracks, the middle stroked with a stroke colour and width track,
    /// under an eased opacity track, plus a hidden layer.
    static func ordered() -> Scene {
        let tri = { (dx: Double, color: Color, stroke: Stroke?) in
            Shape(points: [Point(x: dx, y: 0), Point(x: dx + 30, y: 5), Point(x: dx + 10, y: 40)], fill: .solid(color), stroke: stroke)
        }
        let red = Color(r: 1, g: 0, b: 0), green = Color(r: 0, g: 0.6, b: 0.2), blue = Color(r: 0.1, g: 0.2, b: 1, a: 0.5)
        let layer = Layer(
            id: "stack", name: "Stack",
            shapes: [tri(0, red, nil), tri(20, green, Stroke(color: .black, width: 3)), tri(40, blue, nil)],
            tracks: [
                "opacity": [Keyframe(frame: 0, value: 0.2, easing: .easeInOut), Keyframe(frame: 30, value: 0.9)],
                Layer.trackKey(strokeWidthOf: 1): [Keyframe(frame: 0, value: 1), Keyframe(frame: 40, value: 6)],
            ],
            colorTracks: [
                Layer.colorTrackKey(fillOf: 0): [ColorKeyframe(frame: 0, value: red), ColorKeyframe(frame: 40, value: Color(r: 0, g: 0, b: 0))],
                Layer.colorTrackKey(strokeOf: 1): [ColorKeyframe(frame: 10, value: .black, easing: .hold), ColorKeyframe(frame: 20, value: .white)],
                Layer.colorTrackKey(fillOf: 2): [ColorKeyframe(frame: 0, value: Color(r: 0.1, g: 0.2, b: 1)), ColorKeyframe(frame: 40, value: Color(r: 1, g: 1, b: 0))],
            ]
        )
        let hidden = Layer(id: "off", name: "Off", shapes: [tri(5, green, nil)], isVisible: false)
        return Scene(id: "order", name: "Order", fps: 30, durationFrames: 40, width: 120, height: 60, layers: [layer, hidden])
    }

    /// KJ-VI: every fixture round-trips through SVG and Lottie, and the hand-written SVG reads.
    @Test func walk() throws {
        try Self.svgRoundTrip()
        try Self.lottieRoundTrip()
        try Self.handWrittenSVG()
    }

    // MARK: SVG

    static func svgRoundTrip() throws {
        for (name, document) in try fixtures() {
            let scene = try #require(document.scenes.first)
            let svg = try SVGExporter.export(scene: scene, frame: svgFrame, symbols: document.symbols)
            let (back, _) = try SVGImport.scene(from: Data(svg.utf8), name: name)
            let list = scene.renderList(at: svgFrame, symbols: document.symbols)
            var expected: [(id: String, shapes: [Shape])] = []
            for case .layer(let layer) in SVGExporter.sampled(list.nodes, layers: scene.layers, frame: svgFrame, symbols: document.symbols) {
                let shapes = try drawn(layer.children, ctm: try rounded(layer.transform.matrix), opacity: 1 * (try rounded(layer.opacity)))
                if !shapes.isEmpty { expected.append((layer.id, shapes)) }
            }
            // The background rect reads as the first layer, then the scene's in order.
            #expect(back.layers.map(\.name) == ["rect"] + expected.map(\.id), "\(name): layer order")
            for (layer, want) in zip(back.layers.dropFirst(), expected) {
                #expect(layer.shapes.count == want.shapes.count, "\(name)/\(want.id): shape count")
                for (i, (got, shape)) in zip(layer.shapes, want.shapes).enumerated() {
                    let where_ = "\(name)/\(want.id) shape \(i)"
                    try expectClose(got.outline, shape.outline, within: 1e-6, where_)
                    #expect(got.fill == shape.fill, "\(where_): fill")
                    #expect(got.stroke?.color == shape.stroke?.color, "\(where_): stroke colour")
                    #expect(abs((got.stroke?.width ?? 0) - (shape.stroke?.width ?? 0)) <= 1e-9, "\(where_): stroke width")
                }
            }
        }
    }

    /// The shapes `children` draw as SVGImport reads them back: rounded as the
    /// exporter writes them, placed by `ctm` (the rounded matrices so far) and
    /// faded by `opacity` (the product of the layer opacities so far).
    static func drawn(_ children: [RenderNode], ctm: Matrix, opacity: Double) throws -> [Shape] {
        var out: [Shape] = []
        for child in children {
            switch child {
            case .shape(_, let shape):
                guard !shape.outline.elements.isEmpty else { continue }
                guard case .solid(let color) = shape.fill else {
                    Issue.record("fixture shapes are solid; a gradient needs its own oracle")
                    continue
                }
                var stroke: Stroke?
                if let s = shape.stroke {
                    let width = try rounded(s.width) * abs(ctm.determinant).squareRoot()
                    if width > 0 { stroke = Stroke(color: try paint(s.color, opacity), width: width, join: s.join, cap: s.cap) }
                }
                out.append(Shape(points: [], fill: .solid(try paint(color, opacity)), path: try rounded(shape.outline).transformed(by: ctm), stroke: stroke))
            case .instance(_, let instance, _, _, let nested):
                out += try drawn(nested, ctm: ctm * rounded(instance.transform.matrix), opacity: opacity)
            case .layer(let layer):
                out += try drawn(layer.children, ctm: ctm * rounded(layer.transform.matrix), opacity: opacity * rounded(layer.opacity))
            case .text, .unresolved:
                Issue.record("fixtures draw no text and resolve every instance")
            }
        }
        return out
    }

    /// `value` as the exporter writes it, to 4 decimals.
    static func rounded(_ value: Double) throws -> Double { try #require(Double(try SVGExporter.number(value))) }

    static func rounded(_ m: Matrix) throws -> Matrix {
        Matrix(a: try rounded(m.a), b: try rounded(m.b), c: try rounded(m.c), d: try rounded(m.d), tx: try rounded(m.tx), ty: try rounded(m.ty))
    }

    static func rounded(_ path: Path) throws -> Path {
        let r = { (p: Point) in Point(x: try rounded(p.x), y: try rounded(p.y)) }
        return Path(elements: try path.elements.map { element in
            switch element {
            case .move(let to): .move(to: try r(to))
            case .line(let to): .line(to: try r(to))
            case .quad(let c, let to): .quad(control: try r(c), to: try r(to))
            case .cubic(let c1, let c2, let to): .cubic(control1: try r(c1), control2: try r(c2), to: try r(to))
            case .close: .close
            }
        })
    }

    /// `color` as written in 8-bit hex with its rounded alpha, read back faded by `opacity`.
    static func paint(_ color: Color, _ opacity: Double) throws -> Color {
        let byte = { (v: Double) in Double(Int((min(max(v, 0), 1) * 255).rounded())) / 255 }
        let alpha = min(max(color.a, 0), 1)
        return Color(r: byte(color.r), g: byte(color.g), b: byte(color.b), a: 1 * ((alpha == 1 ? 1 : try rounded(alpha)) * opacity))
    }

    /// Both paths flatten to the same polylines, point by point within `within`.
    /// Repeated points (a closing segment back onto the start) are dropped first.
    static func expectClose(_ got: Path, _ want: Path, within: Double, _ where_: String) throws {
        let a = try polylines(got), b = try polylines(want)
        #expect(a.map(\.count) == b.map(\.count), "\(where_): polyline sizes")
        for (pa, pb) in zip(a, b) {
            for (p, q) in zip(pa, pb) where abs(p.x - q.x) > within || abs(p.y - q.y) > within {
                Issue.record("\(where_): \(p) is not \(q)")
                return
            }
        }
    }

    static func polylines(_ path: Path) throws -> [[Point]] {
        try path.flattened(tolerance: flatten).map { line in
            line.reduce(into: [Point]()) { out, p in
                if let last = out.last, abs(last.x - p.x) <= 1e-9, abs(last.y - p.y) <= 1e-9 { return }
                out.append(p)
            }
        }
    }

    // MARK: Lottie

    static func lottieRoundTrip() throws {
        for (name, document) in try fixtures() {
            let scene = try #require(document.scenes.first)
            let (back, _) = try LottieImport.document(from: try LottieExporter.export(scene: scene, symbols: document.symbols))
            let read = try #require(back.scenes.first)
            #expect(read.fps == scene.fps && read.durationFrames == scene.durationFrames, "\(name): timing")
            #expect(read.width == scene.width && read.height == scene.height, "\(name): size")
            #expect(read.layers.map(\.name) == scene.layers.map(\.name), "\(name): layer order")
            #expect(read.layers.map(\.isVisible) == scene.layers.map(\.isVisible), "\(name): visibility")
            let frames = (0..<sampleCount).map { Double($0 * scene.durationFrames / (sampleCount - 1)) }
            for (got, want) in zip(read.layers, scene.layers) {
                // Instances flatten into extra shapes after the layer's own.
                #expect(got.shapes.count >= want.shapes.count, "\(name)/\(want.id): shape count")
                for frame in frames {
                    let where_ = "\(name)/\(want.id) at \(frame)"
                    let (g, w) = (got.sample(at: frame), want.sample(at: frame))
                    for key in Layer.standardDefaults.keys.sorted() {
                        #expect(abs((g[key] ?? .nan) - (w[key] ?? .nan)) <= 1e-9, "\(where_): \(key)")
                    }
                    for (i, (a, b)) in zip(got.shapes, want.shapes).enumerated() {
                        try expectSame(styled(a, i, got, frame), styled(b, i, want, frame), "\(where_) shape \(i)")
                    }
                }
            }
        }
    }

    /// Shape `i` of `layer` as it draws at `frame`, its path raised to cubics as
    /// Lottie stores it (the exporter's own two-thirds rule).
    static func styled(_ shape: Shape, _ i: Int, _ layer: Layer, _ frame: Double) -> Shape {
        var out = SVGExporter.styled(shape, index: i, of: layer, at: frame)
        var last = Point(x: 0, y: 0), start = last
        out.path = Path(elements: out.outline.elements.map { element in
            defer {
                switch element {
                case .move(let to): (last, start) = (to, to)
                case .line(let to), .quad(_, let to), .cubic(_, _, let to): last = to
                case .close: last = start
                }
            }
            guard case .quad(let c, let to) = element else { return element }
            return .cubic(control1: Point(x: last.x + 2 * (c.x - last.x) / 3, y: last.y + 2 * (c.y - last.y) / 3),
                          control2: Point(x: to.x + 2 * (c.x - to.x) / 3, y: to.y + 2 * (c.y - to.y) / 3), to: to)
        })
        return out
    }

    static func expectSame(_ got: Shape, _ want: Shape, _ where_: String) throws {
        let channels = { (c: Color) in [c.r, c.g, c.b, c.a] }
        switch (got.fill, want.fill) {
        case (.solid(let a), .solid(let b)):
            #expect(zip(channels(a), channels(b)).allSatisfy { abs($0 - $1) <= 1e-9 }, "\(where_): fill \(a) is not \(b)")
        default:
            #expect(got.fill == want.fill, "\(where_): fill")
        }
        #expect((got.stroke == nil) == (want.stroke == nil), "\(where_): stroke")
        if let a = got.stroke, let b = want.stroke {
            #expect(zip(channels(a.color), channels(b.color)).allSatisfy { abs($0 - $1) <= 1e-9 }, "\(where_): stroke \(a.color) is not \(b.color)")
            #expect(abs(a.width - b.width) <= 1e-9, "\(where_): stroke width")
        }
        try expectClose(got.outline, want.outline, within: 1e-9, where_)
    }

    // MARK: Hand-written SVG

    static func handWrittenSVG() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <defs>
        <radialGradient id="glow" cx="50" cy="50" r="20" gradientUnits="userSpaceOnUse">
        <stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#0000ff"/>
        </radialGradient>
        <filter id="soft"><feGaussianBlur stdDeviation="2"/></filter>
        </defs>
        <path id="arc" d="M0 50 A10 10 0 0 1 20 50 Z" fill="#ff0000"/>
        <g id="skew" transform="skewX(45)"><path d="M0 10 L10 10 L10 20 Z" fill="#00ff00"/></g>
        <circle id="disc" cx="50" cy="50" r="20" fill="url(#glow)"/>
        </svg>
        """
        let (scene, report) = try SVGImport.scene(from: Data(svg.utf8), name: "hand")
        #expect(report.skipped.contains("filter (1)"), "\(report.skipped)")
        #expect(scene.layers.map(\.name) == ["arc", "skew", "disc"])
        guard scene.layers.count == 3 else { return }
        // The arc is a half circle of radius 10 about (10, 50).
        let arc = try #require(try scene.layers[0].shapes.first?.outline.flattened(tolerance: flatten).first)
        #expect(arc.count > 4)
        #expect(arc.allSatisfy { abs(((($0.x - 10) * ($0.x - 10)) + (($0.y - 50) * ($0.y - 50))).squareRoot() - 10) <= flatten })
        // skewX(45) maps (x, y) to (x + y, y).
        let skewed = try #require(try scene.layers[1].shapes.first?.outline.flattened(tolerance: flatten).first)
        #expect(skewed.prefix(3).map { [$0.x, $0.y] }.elementsEqual([[10, 10], [20, 10], [30, 20]]) { zip($0, $1).allSatisfy { abs($0 - $1) <= 1e-9 } })
        guard case .radial(let stops, let center, let radius)? = scene.layers[2].shapes.first?.fill else {
            Issue.record("disc fill is not radial")
            return
        }
        #expect(stops.map(\.color) == [.white, Color(r: 0, g: 0, b: 1)])
        #expect(center == Point(x: 50, y: 50) && radius == 20)
    }
}
