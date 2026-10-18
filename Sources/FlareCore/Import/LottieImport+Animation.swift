// LottieImport+Animation.swift: the Lottie reader's keyframes, easings, holds, masks and
// mattes, from the public Lottie format docs. A keyed property (`a: 1`) lists keys of `t`,
// `s` (or the previous `e`), handles `o`/`i`, `h: 1` to hold; two keys or more make a track.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Where a layer's keys land in the scene: frame t + start - ip, in 0...duration.
struct LottieClock: Sendable { var ip = 0, duration = 0, start = 0 }
/// One key as read: its scene frame, its value and the easing to the next key.
struct LottieKey: Sendable { var frame: Int, value: LottieJSON, easing: Easing }
/// The keyed fill colour, stroke colour and stroke width that go with a shape's styles.
struct LottieStyleKeys: Sendable {
    var fill: [ColorKeyframe] = [], stroke: [ColorKeyframe] = [], width: [Keyframe] = []
    /// These keys where this group has its own fill or stroke, else `other`'s.
    func over(_ other: LottieStyleKeys, fill hasFill: Bool, stroke hasStroke: Bool) -> LottieStyleKeys {
        LottieStyleKeys(fill: hasFill ? fill : other.fill, stroke: hasStroke ? stroke : other.stroke,
                        width: hasStroke ? width : other.width)
    }
    /// The keys with every alpha times `opacity`.
    func faded(_ opacity: Double) -> LottieStyleKeys {
        func fade(_ keys: [ColorKeyframe]) -> [ColorKeyframe] { keys.map { var key = $0; key.value.a *= opacity; return key } }
        return LottieStyleKeys(fill: fade(fill), stroke: fade(stroke), width: width)
    }
}
/// A shape as read, with the keys its tracks get once its index is known.
struct LottieShape: Sendable { var shape: Shape, keys = LottieStyleKeys(), path: [PathKeyframe] = [] }
/// A keyed `sh`: where its elements sit in the group's geometry, and its keys' elements.
struct LottieKeyedPart: Sendable { var range: Range<Int>, keys: [PathKeyframe] }

extension LottieReader {
    /// The keys of `k`, each `t` checked, sorted and mapped into the scene.
    mutating func keyframes(_ k: LottieJSON?) throws -> [LottieKey] {
        guard let list = k?.array else { throw ImportError.damaged("keyframes are not an array") }
        guard list.count <= FlareFormat.maxKeysPerTrack else { throw ImportError.tooLarge("\(list.count) keyframes, over the track limit") }
        var out: [LottieKey] = [], last = 0, previous: LottieJSON?
        for key in list {
            let t = try frame(key["t"], "keyframe t", 0, LottieImport.frames)
            guard t >= last else { throw ImportError.damaged("keyframe t \(t) comes after \(last)") }
            last = t
            guard let value = key["s"] ?? previous else { throw ImportError.damaged("keyframe has no value") }
            previous = key["e"] ?? value
            let scene = t + clock.start - clock.ip, f = min(max(scene, 0), clock.duration)
            if f != scene { skip("keyframe outside scene") }
            let read = LottieKey(frame: f, value: value, easing: try easing(key))
            // Keys clamped onto one frame: before the scene the latest wins, after it the first.
            if let prior = out.last, prior.frame == f {
                if scene <= clock.duration { out[out.count - 1] = read }
            } else { out.append(read) }
        }
        return out
    }
    /// A key's easing to the next: `h` holds, `o`/`i` handles a cubic bezier, else linear.
    func easing(_ key: LottieJSON) throws -> Easing {
        if key["h"]?.isTrue ?? false { return .hold }
        guard let o = key["o"], let i = key["i"] else { return .linear }
        func handle(_ json: LottieJSON?) throws -> Double { try number(json?.array?.first ?? json, "easing handle", 0) }
        let x1 = min(max(try handle(o["x"]), 0), 1), y1 = try handle(o["y"])
        let x2 = min(max(try handle(i["x"]), 0), 1), y2 = try handle(i["y"])
        if x1 == 0, y1 == 0, x2 == 1, y2 == 1 { return .linear }
        return .cubicBezier(x1: x1, y1: y1, x2: x2, y2: y2)
    }
    /// Value `component` of each key of a keyed property, through `map`; empty under two keys.
    mutating func track(_ property: LottieJSON?, _ component: Int, map: (Double) -> Double = { $0 }) throws -> [Keyframe] {
        guard let property, property["a"]?.isTrue ?? false else { return [] }
        let keys = try keyframes(property["k"])
        guard keys.count > 1 else { return [] }
        return try keys.map { key in
            let values = key.value.array ?? [key.value]
            guard values.indices.contains(component) else { throw ImportError.damaged("keyframe needs \(component + 1) values") }
            let v = map(try number(values[component], "keyframe value", 0))
            guard v.isFinite else { throw ImportError.damaged("keyframe value is not finite") }
            return Keyframe(frame: key.frame, value: v, easing: key.easing)
        }
    }
    /// The layer tracks a `ks` keys: x and y (combined or split `p`), scale, rotation and opacity.
    mutating func transformTracks(_ ks: LottieJSON?) throws -> [String: [Keyframe]] {
        let p = ks?["p"], split = p?["s"]?.isTrue ?? false
        let curved = (p?["k"]?.array ?? []).contains { key in
            ["ti", "to"].contains { (key[$0]?.array ?? []).contains { $0 != .number(0) } }
        }
        if !split, curved, p?["a"]?.isTrue ?? false { skip("position path") }
        let out = ["x": try track(split ? p?["x"] : p, 0), "y": try track(split ? p?["y"] : p, split ? 0 : 1),
                   "scaleX": try track(ks?["s"], 0) { $0 / 100 }, "scaleY": try track(ks?["s"], 1) { $0 / 100 },
                   "rotation": try track(ks?["r"], 0), "opacity": try track(ks?["o"], 0) { min(max($0 / 100, 0), 1) }]
        return out.filter { !$0.value.isEmpty }
    }
    /// The colour keys of a keyed `c`, each with alpha `alpha`; empty under two keys.
    mutating func colorKeys(_ c: LottieJSON?, alpha: Double) throws -> [ColorKeyframe] {
        guard c?["a"]?.isTrue ?? false else { return [] }
        let keys = try keyframes(c?["k"])
        guard keys.count > 1 else { return [] }
        return try keys.map { key in
            let v = try (key.value.array ?? []).map { try number($0, "color", 0) }
            return ColorKeyframe(frame: key.frame, value: try Self.rgb(v, a: alpha), easing: key.easing)
        }
    }
    /// Channels `c` (at least r, g, b), clamped to 0...1, with alpha `a`.
    static func rgb(_ c: [Double], a: Double) throws -> Color {
        guard c.count >= 3 else { throw ImportError.damaged("color needs three channels") }
        return Color(r: min(max(c[0], 0), 1), g: min(max(c[1], 0), 1), b: min(max(c[2], 0), 1), a: a)
    }
    /// Appends an `sh` to `geometry`, and its keys to `keyed` when it is keyed.
    mutating func outline(_ property: LottieJSON?, matrix: Matrix, into geometry: inout [PathElement], keyed: inout [LottieKeyedPart]) throws {
        let start = geometry.count
        geometry += try bezier(property).transformed(by: matrix).elements
        guard property?["a"]?.isTrue ?? false else { return }
        let keys = try keyframes(property?["k"]).map { key in
            PathKeyframe(frame: key.frame, path: try path(key.value.array?.first ?? key.value).transformed(by: matrix), easing: key.easing)
        }
        keyed.append(LottieKeyedPart(range: start..<geometry.count, keys: keys))
    }
    /// The group's path at each key of its keyed parts, when they all key the same frames.
    mutating func pathKeys(_ geometry: [PathElement], _ keyed: [LottieKeyedPart]) -> [PathKeyframe] {
        guard let first = keyed.first else { return [] }
        let frames = first.keys.map(\.frame)
        guard keyed.allSatisfy({ $0.keys.map(\.frame) == frames }) else { skip("animated property", keyed.count); return [] }
        guard frames.count > 1 else { return [] }
        return first.keys.indices.map { k in
            var elements = geometry
            for part in keyed.reversed() { elements.replaceSubrange(part.range, with: part.keys[k].path.elements) }
            return PathKeyframe(frame: frames[k], path: Path(elements: elements), easing: first.keys[k].easing)
        }
    }
    /// Sets `layer`'s shapes, bottom first, and the colour, width and shape tracks their keys make.
    func place(_ shapes: [LottieShape], on layer: inout Layer) {
        layer.shapes = shapes.map(\.shape)
        for (index, read) in shapes.enumerated() {
            if read.keys.fill.count > 1 { layer.colorTracks[Layer.colorTrackKey(fillOf: index)] = read.keys.fill }
            if read.keys.stroke.count > 1 { layer.colorTracks[Layer.colorTrackKey(strokeOf: index)] = read.keys.stroke }
            if read.keys.width.count > 1 { layer.tracks["strokeWidth.\(index)"] = read.keys.width }
            if read.path.count > 1 { layer.shapeTracks.append(ShapeTrack(shapeIndex: index, keys: read.path)) }
        }
    }
    /// `masksProperties` as masks in layer space; other modes, and masks past the limit, are counted.
    mutating func masks(_ list: [LottieJSON], root: Matrix) throws -> [LayerMask] {
        let modes: [String: MaskMode] = ["a": .add, "s": .subtract, "i": .intersect, "f": .difference]
        defer { animatedKind = "animated property" }
        animatedKind = "mask animation"
        var out: [LayerMask] = []
        for json in list {
            guard let mode = modes[json["mode"]?.string ?? "a"] else { skip("mask mode"); continue }
            guard out.count < FlareFormat.maxMasksPerLayer else { skip("mask"); continue }
            if json["pt"]?["a"]?.isTrue ?? false { skip("mask animation") }
            let opacity = min(max(try scalar(json["o"], "mask opacity", 100) / 100, 0), 1)
            if try scalar(json["x"], "mask expansion", 0) != 0 { skip("mask expansion") }
            let path = try bezier(json["pt"]).transformed(by: root)
            out.append(LayerMask(path: path, mode: mode, opacity: opacity, inverted: json["inv"]?.isTrue ?? false))
        }
        return out
    }
    /// Sets each `tt` layer's matte from the `tp` layer by `ind`, else the one above;
    /// `built` maps a file index to its index in `out`.
    mutating func linkMattes(_ out: inout [Layer], _ layers: [LottieJSON], built: [Int: Int]) {
        let kinds: [Double: MatteKind] = [1: .alpha, 2: .alphaInverted, 3: .luma, 4: .lumaInverted]
        for (index, json) in layers.enumerated() {
            guard let tt = json["tt"], tt != .number(0), let target = built[index] else { continue }
            let above = index > 0 ? index - 1 : nil
            let from = json["tp"].map { tp in layers.firstIndex { $0["ind"] == tp } } ?? above
            guard case .number(let n) = tt, let kind = kinds[n], let from, from != index, let source = built[from],
                  out.indices.contains(target), out.indices.contains(source) else { skip("matte"); continue }
            out[target].matte = TrackMatte(sourceLayerID: out[source].id, kind: kind)
        }
    }
}
