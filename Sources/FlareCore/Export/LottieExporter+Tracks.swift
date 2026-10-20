// LottieExporter+Tracks.swift: animated Lottie properties and keyframes written from layer tracks.
//
// A shape's keyed fill colour (`fl.c`), stroke colour (`st.c`), stroke width
// (`st.w`, the `Layer.trackKey(strokeWidthOf:)` track) and path (`sh.ks`) animate when the
// track has two keys or more: one keyframe per key, `o`/`i` from its easing
// (hold: `h: 1`) as for position. A colour is `[r, g, b, a]` clamped to 0...1,
// and `o` is its alpha times 100: animated from the same keys when their
// alphas differ (players fade from `o`, not `c`'s 4th value). A path key
// is one bezier per subpath, tangents relative to their vertex; two path keys
// whose anchors do not pair up hold the left one, as the sampler does, and
// keys with different subpath counts throw `unsupported("shape track")`. A
// single key, or a layer inside a symbol (drawn at one local frame), writes
// the sampled value statically. A keyed fill paints a gradient shape solid. A
// stroke whose trim (`Stroke.trim` with its `trimStart/End/Offset.<i>` tracks
// sampled in) cuts the outline, or whose trim tracks animate, splits the group:
// first a group of the subpaths, a trim (`tm`: `s` and `e` in percent, `o` in
// degrees, `m` 2 together or 1 each contour) and the stroke, then a group of the
// subpaths and the fill, so the fill stays whole. A shape with no keys and no
// trim writes exactly what `init(shape:)` writes.

/// A scalar property, animated from one track.
typealias LottieScalar = LottieProperty<Double>

extension LottieProperty where Value == Double {
    /// `at0` is the track's finite value at frame 0, used when it has under two
    /// keyframes. `map` turns a finite track value into the written one.
    init(_ track: [Keyframe], at0: Double, map: (Double) -> Double = { $0 }) throws {
        guard track.count > 1 else {
            self = .fixed(LottieStatic(map(at0)))
            return
        }
        self = .animated(try LottieKeyframe.list(track) { _, key in [map(try LottieExporter.finite(key.value))] })
    }
}

extension LottieProperty where Value == [Double] {
    /// A layer's 2-D scale, times 100, from its `scaleX` and `scaleY` tracks.
    /// `x0` and `y0` are the finite scales at frame 0.
    init(scaleOf layer: Layer, x0: Double, y0: Double, durationFrames: Int) throws {
        let xs = layer.tracks["scaleX"] ?? []
        let ys = layer.tracks["scaleY"] ?? []
        // Checked after the times 100: a finite 1e307 becomes infinity.
        func f(_ v: Double) throws -> Double { try LottieExporter.finite(v * 100) }
        func still() throws -> Self { .fixed(LottieStatic([try f(x0), try f(y0)])) }
        if xs.count <= 1, ys.count <= 1 {
            self = try still()
        } else if ys.count <= 1 {
            let y = try f(y0)
            self = .animated(try LottieKeyframe.list(xs) { _, key in [try f(key.value), y] })
        } else if xs.count <= 1 {
            let x = try f(x0)
            self = .animated(try LottieKeyframe.list(ys) { _, key in [x, try f(key.value)] })
        } else if xs.count == ys.count,
                  zip(xs, ys).allSatisfy({ $0.frame == $1.frame && $0.easing == $1.easing }) {
            self = .animated(try LottieKeyframe.list(xs) { index, key in [try f(key.value), try f(ys[index].value)] })
        } else {
            // Checked before hi: durationFrames - 1 overflows on Int.min.
            guard durationFrames > 0 else {
                self = try still()
                return
            }
            let frames = (xs + ys).map(\.frame)
            let lo = max(0, frames.min() ?? 0)
            let hi = min(durationFrames - 1, frames.max() ?? 0)
            // lo >= 0 keeps hi - lo + 1 in range.
            guard lo <= hi else {
                self = try still()
                return
            }
            guard hi - lo + 1 <= LottieExporter.maxBakedKeys else {
                throw LottieExportError.unsupported("scale track")
            }
            var baked: [LottieKeyframe] = []
            baked.reserveCapacity(hi - lo + 1)
            for frame in lo...hi {
                let s = layer.sample(at: Double(frame))
                let key = LottieKeyframe(t: frame, s: [try f(s["scaleX"] ?? 1), try f(s["scaleY"] ?? 1)])
                baked.append(frame < hi ? key.eased(.linear) : key)
            }
            self = .animated(baked)
        }
    }
}

/// One keyframe of an animated property. The last one carries only `t` and `s`.
struct LottieKeyframe: Encodable, Sendable {
    var t: Int
    var s: LottieKeyValue
    var o: LottieEase?
    var i: LottieEase?
    var h: Int?

    init(t: Int, s: LottieKeyValue) { (self.t, self.s) = (t, s) }
    init(t: Int, s: [Double]) { self.init(t: t, s: .numbers(s)) }

    /// One keyframe per track key, `value` giving each one's `s` from its index
    /// and key; every keyframe but the last carries its key's easing.
    static func list(_ track: [Keyframe], value: (Int, Keyframe) throws -> [Double]) throws -> [LottieKeyframe] {
        try list(Array(track.enumerated()), frame: \.element.frame, value: { .numbers(try value($0.offset, $0.element)) },
                 easing: { key, _ in key.element.easing })
    }

    /// One keyframe per key at `frame(key)` with `s` from `value`; every one
    /// but the last eased by `easing` of that key and the next.
    static func list<Key>(_ keys: [Key], frame: (Key) -> Int, value: (Key) throws -> LottieKeyValue,
                          easing: (Key, Key) -> Easing) throws -> [LottieKeyframe] {
        try zip(keys, keys.dropFirst().map(Optional.some) + [nil]).map { key, next in
            let out = LottieKeyframe(t: frame(key), s: try value(key))
            return next.map { out.eased(easing(key, $0)) } ?? out
        }
    }

    /// This keyframe with `easing` written as `h: 1` for hold or `o`/`i` tangents.
    func eased(_ easing: Easing) -> LottieKeyframe {
        var out = self
        switch easing {
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
        return out
    }
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

/// A keyframe's `s`: numbers, or a shape key's one bezier per subpath.
enum LottieKeyValue: Encodable, Sendable {
    case numbers([Double])
    case shapes([LottieBezier])

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .numbers(let values): try container.encode(values)
        case .shapes(let beziers): try container.encode(beziers)
        }
    }
}

extension LottieExporter {
    /// `value` clamped to 0...1; non-finite throws.
    static func unit(_ value: Double) throws -> Double { min(max(try finite(value), 0), 1) }

    /// `color` as `[r, g, b, a]`, each in 0...1.
    static func rgba(_ color: Color) throws -> [Double] {
        [try unit(color.r), try unit(color.g), try unit(color.b), try unit(color.a)]
    }
}

extension LottieItem {
    /// Shape `index` of `layer` as `init(shape:)` writes it, with the fill and
    /// stroke colours, stroke width, path and stroke trim its tracks key: animated
    /// when `animate` (a scene layer), else their values at `frame` (a symbol's layer).
    init(shape: Shape, index: Int, of layer: Layer, frame: Double, animate: Bool) throws {
        try self.init(shape: shape)
        if let items = it { it = try Self.keyed(items, shape: shape, index: index, of: layer, frame: frame, animate: animate) }
        try trim(shape, index: index, of: layer, frame: frame, animate: animate)
    }

    /// `items`, the shape group `init(shape:)` wrote for `layer.shapes[index]`, with its fill, stroke and path tracks.
    static func keyed(_ items: [LottieItem], shape: Shape, index: Int, of layer: Layer, frame: Double, animate: Bool) throws -> [LottieItem] {
        var items = items
        let widthKey = Layer.trackKey(strokeWidthOf: index)
        let fills = layer.colorTracks[Layer.colorTrackKey(fillOf: index)] ?? []
        let strokes = layer.colorTracks[Layer.colorTrackKey(strokeOf: index)] ?? []
        let widths = layer.tracks[widthKey] ?? []
        let paths = layer.shapeTracks.first { $0.shapeIndex == index }?.keys ?? []
        guard !(fills.isEmpty && strokes.isEmpty && widths.isEmpty && paths.isEmpty) else { return items }
        if let outline = try Self.outline(paths, of: layer, index, frame: frame, animate: animate) {
            items = outline + items.filter { $0.ty != "sh" }
        }
        for k in items.indices {
            switch items[k].ty {
            case "fl", "gf":
                guard !fills.isEmpty else { continue }
                var paint = LottieItem(ty: "fl")
                paint.r = .rule(1)
                items[k] = try paint.coloured(fills, .fill(shape: index), of: layer, frame: frame, animate: animate)
            case "st":
                items[k] = try items[k].coloured(strokes, .stroke(shape: index), of: layer, frame: frame, animate: animate)
                guard !widths.isEmpty else { continue }
                let now = try LottieExporter.finite(layer.sample(at: frame)[widthKey] ?? shape.stroke?.width ?? 0)
                items[k].w = try LottieScalar(animate ? widths : [], at0: now)
            default: continue
            }
        }
        return items
    }

    /// Splits this shape group in two when its stroke is trimmed: the subpaths,
    /// a `tm` and the stroke, then the subpaths and the fill. Unchanged without
    /// a stroke, or when the trim keeps the whole outline and no trim track animates.
    mutating func trim(_ shape: Shape, index: Int, of layer: Layer, frame: Double, animate: Bool) throws {
        let keys = [Layer.trackKey(trimStartOf: index), Layer.trackKey(trimEndOf: index), Layer.trackKey(trimOffsetOf: index)]
        let tracks = keys.map { animate ? layer.tracks[$0] ?? [] : [] }
        guard let stroke = shape.stroke, let now = layer.sampledTrim(of: index, base: stroke.trim, at: frame),
              !now.isWhole || tracks.contains(where: { $0.count > 1 }), let items = it else { return }
        // Checked here: map cannot throw, and a finite turn count can overflow in degrees.
        for value in [now.offset] + tracks[2].map(\.value) { _ = try LottieExporter.finite(value * 360) }
        func percent(_ v: Double) -> Double { min(max(v, 0), 1) * 100 }
        var tm = LottieItem(ty: "tm")
        tm.s = .percent(try LottieScalar(tracks[0], at0: now.start, map: percent))
        tm.e = .percent(try LottieScalar(tracks[1], at0: now.end, map: percent))
        tm.o = try LottieScalar(tracks[2], at0: now.offset) { $0 * 360 }
        tm.m = now.mode == .together ? 2 : 1
        let subpaths = items.filter { $0.ty == "sh" }
        let identity = try LottieItem.transform(.identity, opacity: 1)
        it = [LottieExporter.group(subpaths + [tm] + items.filter { $0.ty == "st" } + [identity]),
              LottieExporter.group(subpaths + items.filter { $0.ty == "fl" || $0.ty == "gf" } + [identity])]
            + items.filter { $0.ty == "tr" }
    }

    /// This item with `c` and `o` from colour track `keys` of `target`:
    /// animated, or its colour at `frame`. Unchanged when the track is empty.
    func coloured(_ keys: [ColorKeyframe], _ target: TrackTarget, of layer: Layer, frame: Double, animate: Bool) throws -> LottieItem {
        guard let now = layer.sampledColor(target, at: frame) else { return self }
        var out = self
        out.o = .fixed(LottieStatic(try LottieExporter.unit(now.a) * 100))
        if animate, keys.count > 1 {
            out.c = .animated(try LottieKeyframe.list(keys, frame: \.frame, value: { .numbers(try LottieExporter.rgba($0.value)) },
                                                       easing: { key, _ in key.easing }))
            if keys.contains(where: { $0.value.a != keys.first?.value.a }) {
                out.o = .animated(try LottieKeyframe.list(keys, frame: \.frame, value: { .numbers([try LottieExporter.unit($0.value.a) * 100]) },
                                                           easing: { key, _ in key.easing }))
            }
        } else {
            out.c = .fixed(LottieStatic(Array(try LottieExporter.rgba(now).prefix(3)) + [1]))
        }
        return out
    }

    /// One `sh` per subpath of shape track `keys`: animated, or the path at
    /// `frame`. nil when the track is empty.
    static func outline(_ keys: [PathKeyframe], of layer: Layer, _ index: Int, frame: Double, animate: Bool) throws -> [LottieItem]? {
        func sh(_ ks: LottieProperty<LottieBezier>) -> LottieItem {
            var item = LottieItem(ty: "sh")
            item.ks = ks
            return item
        }
        guard animate, keys.count > 1 else {
            return try layer.sampledPath(shape: index, at: frame).map { try LottieExporter.beziers($0).map { sh(.fixed(LottieStatic($0))) } }
        }
        let shapes = try keys.map { ($0, try LottieExporter.beziers($0.path)) }
        let parts = shapes.first?.1.count ?? 0
        guard shapes.allSatisfy({ $0.1.count == parts }) else { throw LottieExportError.unsupported("shape track") }
        // Keys tween only when their anchors pair up for both the sampler and a Lottie player.
        func tweens(_ a: (PathKeyframe, [LottieBezier]), _ b: (PathKeyframe, [LottieBezier])) -> Bool {
            zip(a.1, b.1).allSatisfy { $0.v.count == $1.v.count && $0.c == $1.c } && Path.morph(a.0.path, b.0.path, 0) != nil
        }
        return try (0..<parts).map { part in
            sh(.animated(try LottieKeyframe.list(shapes, frame: { $0.0.frame }, value: { .shapes([$0.1[part]]) },
                                                 easing: { tweens($0, $1) ? $0.0.easing : .hold })))
        }
    }
}
