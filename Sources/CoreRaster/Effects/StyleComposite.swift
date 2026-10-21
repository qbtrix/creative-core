// StyleComposite.swift: a layer style stack drawn over its layer
// (layer-style-engine LE-4). Each enabled entry with opacity above 0 becomes
// one premultiplied light layer (two for a bevel) the buffer's size, and the
// layers go down in a fixed paint order whatever the list order: under the
// layer, drop shadow, outer glow, outside stroke, each knocked out by the
// layer's alpha; then the layer at the fill opacity, added to them (they are
// knocked out already, so a src-over would weight them by (1 - a) twice, and
// a lone shadow or outside stroke equals `shadowed` or `stroked`); then over
// it, clipped to its alpha, gradient overlay, colour overlay, inner glow,
// inner shadow; then the bevel's shadow and highlight (already clipped by
// `beveled`) and the inside (clipped) and centre strokes. Entries of one kind
// keep their list order. Each layer composites with its entry's mode and
// opacity (a bevel's with its own two modes, times the entry's opacity); the
// fill opacity fades only the layer. There is no backdrop: an under-layer's
// mode applies among the under-layers, so the bottom one draws as Normal.
// Shadows and glows reuse the glows' blurred alpha: `spread` first grows the
// shape (or, inner, its complement) by spread x size on the distance field, then the blur runs over the rest, so spread 1 is a hard
// edge. A clipped layer composites onto the canvas made opaque, and the result
// is weighted by the canvas alpha inside the clip; where the clip is not yet
// covered (fill opacity under 1) the layer shows on its own, so a clipped
// layer never adds alpha outside the layer's shape and adds none at all where
// the layer is drawn in full. Invariants: no active entry at fill opacity 1
// returns the buffer itself; the result is the buffer's size and finite; a
// NaN, infinite or over-cap value, an opacity or spread outside 0...1, or more
// than `maxEntries` entries throws `RasterError.invalid`; each entry's layers
// are composited before the next entry's are drawn, so at most two are alive.

/// Where a light layer goes: under the layer, over it clipped to its alpha, or over it as it is.
package enum StylePlacement: Sendable, Hashable { case under, clipped, over }

/// One premultiplied light layer of an entry, ready to composite. Equatable, not Hashable, as `PixelBuffer` is.
package struct StyleLayer: Sendable, Equatable {
    package var source: PixelBuffer, mode: BlendMode, opacity: Float, placement: StylePlacement
}

extension StyleOp {
    /// The op's place in the fixed paint order, bottom up.
    var paintRank: Int {
        switch self {
        case .dropShadow: 0
        case .outerGlow: 1
        case .stroke(_, _, .outside): 2
        case .overlay(.gradient): 3
        case .overlay(.color): 4
        case .innerGlow: 5
        case .innerShadow: 6
        case .bevel: 7
        case .stroke(_, _, .inside): 8
        case .stroke: 9
        }
    }

    /// The op's name in errors.
    var name: String {
        switch self {
        case .dropShadow: "drop shadow"
        case .innerShadow: "inner shadow"
        case .outerGlow: "outer glow"
        case .innerGlow: "inner glow"
        case .stroke: "stroke"
        case .overlay: "overlay"
        case .bevel: "bevel"
        }
    }
}

extension LayerStyleStack {
    /// The largest reach, so a caller's padding stays a sane allocation.
    static let maxReach = 1_000_000.0

    /// The most entries `styled` draws; a longer stack throws `RasterError.invalid`.
    /// A file's layer has one entry per effect kind and few instances of
    /// each, far below this.
    public static let maxEntries = 64

    /// The px a caller pads on each side so nothing the stack draws clips:
    /// the most any enabled entry draws past the layer's edge (a drop
    /// shadow's offset length plus its blur, an outer glow's size, an
    /// outside stroke's width, half a centre stroke's, an outer bevel's or
    /// emboss's size), rounded up. A NaN counts as 0 and the total is capped
    /// at `maxReach`; `styled` throws on those values anyway.
    public var reach: Int {
        var most = 0.0
        for entry in entries where entry.isEnabled {
            let far: Double
            switch entry.op {
            case let .dropShadow(_, dx, dy, _, blur): far = (dx * dx + dy * dy).squareRoot() + blur
            case let .outerGlow(_, _, size): far = size
            case .stroke(_, let width, .outside): far = width
            case .stroke(_, let width, .center): far = width / 2
            case let .bevel(bevel) where bevel.shape != .innerBevel: far = bevel.size
            default: far = 0
            }
            if !far.isNaN { most = max(most, far) }
        }
        return Int(min(most, Self.maxReach).rounded(.up))
    }
}

extension PixelBuffer {
    /// The layer drawn with `stack`, the same size, in the fixed paint order
    /// (see the file header). Nothing is drawn past the buffer's edge, so pad
    /// the layer by `stack.reach` px on each side first, or a drop shadow,
    /// outer glow, outside stroke or outer bevel is cut off at the edge with
    /// no error. Each entry's light layers are composited as soon as they are
    /// drawn, so memory stays a few buffers whatever the entry count. Throws
    /// `RasterError.invalid` for more than `LayerStyleStack.maxEntries`
    /// entries, a fill opacity or entry opacity outside 0...1, and an active
    /// entry with a NaN, infinite or over-cap value (spread outside 0...1,
    /// blur or size outside 0...1,000, stroke width outside 0...1,000, a
    /// bevel `beveled` refuses).
    public func styled(_ stack: LayerStyleStack) throws -> PixelBuffer {
        guard stack.entries.count <= LayerStyleStack.maxEntries else {
            throw RasterError.invalid("style stack of \(stack.entries.count) entries: at most \(LayerStyleStack.maxEntries)")
        }
        guard (0...1).contains(stack.fillOpacity) else {
            throw RasterError.invalid("fill opacity \(stack.fillOpacity): must be a finite value in 0...1")
        }
        for (i, entry) in stack.entries.enumerated() where !(0...1).contains(entry.opacity) {
            throw RasterError.invalid("style entry \(i) (\(entry.op.name)) opacity \(entry.opacity): must be a finite value in 0...1")
        }
        let active = stack.entries.enumerated().filter { $0.element.isEnabled && $0.element.opacity > 0 }
            .sorted { ($0.element.op.paintRank, $0.offset) < ($1.element.op.paintRank, $1.offset) }
        guard !active.isEmpty || stack.fillOpacity < 1 else { return self }
        // Under-layers (ranks 0-2) sort first, so the layer is added once, before the first layer over it.
        var canvas = try PixelBuffer(width: width, height: height), filled = false
        for entry in active {
            for layer in try styleLayers(entry.element) {
                if layer.placement == .under {
                    try canvas.composite(layer.source, x: 0, y: 0, mode: layer.mode, opacity: layer.opacity)
                    continue
                }
                if !filled { (canvas, filled) = (try adding(onto: canvas, fillOpacity: stack.fillOpacity), true) }
                if layer.placement == .clipped {
                    try canvas.compositeClipped(layer, clip: self)
                } else {
                    try canvas.composite(layer.source, x: 0, y: 0, mode: layer.mode, opacity: layer.opacity)
                }
            }
        }
        return filled ? canvas : try adding(onto: canvas, fillOpacity: stack.fillOpacity)
    }

    /// `under` plus this layer at `fillOpacity`: the under-layers are knocked out already, so the layer is added.
    private func adding(onto under: PixelBuffer, fillOpacity: Float) throws -> PixelBuffer {
        var sum = under.components
        let src = components
        for i in sum.indices {
            sum[i] += src[i] * fillOpacity
            guard sum[i].isFinite else { throw RasterError.invalid("styled layer: result overflows") }
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: sum)
    }

    /// The entry's light layers, each the buffer's size.
    package func styleLayers(_ entry: StyleEntry) throws -> [StyleLayer] {
        func one(_ source: PixelBuffer, _ placement: StylePlacement) -> [StyleLayer] {
            [StyleLayer(source: source, mode: entry.mode, opacity: entry.opacity, placement: placement)]
        }
        switch entry.op {
        case let .dropShadow(color, dx, dy, spread, blur):
            return one(try lightLayer(color, dx, dy, spread, blur, inner: false, effect: entry.op.name, reachName: "blur"), .under)
        case let .innerShadow(color, dx, dy, spread, blur):
            return one(try lightLayer(color, dx, dy, spread, blur, inner: true, effect: entry.op.name, reachName: "blur"), .clipped)
        case let .outerGlow(color, spread, size):
            return one(try lightLayer(color, 0, 0, spread, size, inner: false, effect: entry.op.name, reachName: "size"), .under)
        case let .innerGlow(color, spread, size):
            return one(try lightLayer(color, 0, 0, spread, size, inner: true, effect: entry.op.name, reachName: "size"), .clipped)
        case let .stroke(fill, width, position):
            let placement: StylePlacement = position == .outside ? .under : position == .inside ? .clipped : .over
            return one(try strokeLayer(fill, width: width, position: position), placement)
        case let .overlay(fill):
            return one(try fillLayer(fill), .clipped)
        case let .bevel(bevel):
            let (highlight, shadow) = try beveled(bevel)
            return [StyleLayer(source: shadow, mode: bevel.shadowMode, opacity: entry.opacity, placement: .over),
                    StyleLayer(source: highlight, mode: bevel.highlightMode, opacity: entry.opacity, placement: .over)]
        }
    }

    /// A shadow or glow alone: premultiplied `color` times the spread and
    /// blurred alpha (its complement when `inner`) read at (`dx`, `dy`) back;
    /// an outer one is knocked out by the layer's alpha, an inner one is left
    /// unclipped for `compositeClipped`. `reachName` names `size` in errors.
    func lightLayer(_ color: RGBA, _ dx: Double, _ dy: Double, _ spread: Double, _ size: Double,
                    inner: Bool, effect: String, reachName: String) throws -> PixelBuffer {
        guard color.isFinite, dx.isFinite, dy.isFinite else {
            throw RasterError.invalid("\(effect) color \(color) at (\(dx), \(dy)): must be finite")
        }
        guard (0...1).contains(spread) else { throw RasterError.invalid("\(effect) spread \(spread): must be finite and in 0...1") }
        try Self.checkLightReach(size, effect: effect, reachName: reachName)
        let choke = spread * size, blur = size - choke
        let work = Self.lightWork(effect: effect, reachName: reachName, reach: blur, dx: dx, dy: dy)
        let mask = try spreadAlpha(choke: choke, inner: inner)
            .blurredAlpha(reach: blur, inner: inner, pad: work.pad, cause: work.cause, remedy: work.remedy)
        let src = components, c = Self.channels, paint = [color.r, color.g, color.b, color.a]
        var out = [Float](repeating: 0, count: src.count)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * c
                // Multiplied in `shadowed`'s order, so a lone drop shadow equals it.
                let cover = Float(mask.sample(Double(x) - dx, Double(y) - dy))
                let knock: Float = inner ? 1 : 1 - min(max(src[o + 3], 0), 1)
                guard cover * knock > 0 else { continue }
                for k in 0..<c { out[o + k] = paint[k] * cover * knock }
            }
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: out)
    }

    /// This buffer's alpha grown by `choke` px past the edge, or with the
    /// edge pulled in by `choke` px when `inner`, a one-pixel ramp at the new
    /// edge on the distance field between pixel centres. Choke 0 is the buffer itself.
    func spreadAlpha(choke: Double, inner: Bool) throws -> PixelBuffer {
        guard choke > 0 else { return self }
        let field = try DistanceField(alpha: self), c = Self.channels
        var data = components
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * c
                let d = Double(inner ? field.inside(x: x, y: y) : field.outside(x: x, y: y))
                let grown = Float(min(max(choke - d + 1, 0), 1))
                data[o + 3] = inner ? min(data[o + 3], 1 - grown) : max(data[o + 3], grown)
            }
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: data)
    }

    /// A stroke alone, in `fill`: outside knocked out by the layer's alpha,
    /// inside left unclipped for `compositeClipped`, centre as it is. The
    /// coverage is `stroked`'s, on the same anti-aliased edge distances.
    func strokeLayer(_ fill: StyleFill, width strokeWidth: Double, position: StrokePosition) throws -> PixelBuffer {
        try Self.checkStrokeWidth(strokeWidth)
        let paint = try fillLayer(fill)
        guard strokeWidth > 0 else { return try PixelBuffer(width: width, height: height) }
        let distance = try edgeDistances(), src = components, c = Self.channels
        var out = paint.components
        for i in 0..<(width * height) {
            let o = i * c, alpha = src[o + 3], inShape = alpha >= 0.5
            let cover: Float, knock: Float = position == .outside ? 1 - min(max(alpha, 0), 1) : 1
            switch position {
            case .outside: cover = inShape ? 1 : Self.coverage(edge: distance[i], width: strokeWidth)
            case .inside: cover = inShape ? Self.coverage(edge: distance[i], width: strokeWidth) : 1
            case .center: cover = Self.coverage(edge: distance[i], width: strokeWidth / 2)
            }
            // Multiplied in `stroked`'s order, so a lone outside stroke equals it.
            for k in 0..<c { out[o + k] = out[o + k] * cover * knock }
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: out)
    }

    /// `fill` over the whole buffer: a colour flood, or `RasterGradient`'s
    /// ramp in this buffer's pixel space.
    package func fillLayer(_ fill: StyleFill) throws -> PixelBuffer {
        switch fill {
        case let .color(color):
            guard color.isFinite else { throw RasterError.invalid("style fill color \(color): must be finite") }
            return try PixelBuffer(width: width, height: height, fill: color)
        case let .gradient(stops, shape, from, to):
            return try Self.gradient(width: width, height: height, shape: shape, from: from, to: to, stops: stops)
        }
    }

    /// `layer` over this canvas, clipped to `clip`'s alpha. Where the canvas
    /// covers the clip, the layer composites with its mode onto the canvas
    /// made opaque and is weighted by the canvas alpha, so no alpha is added;
    /// canvas alpha past the clip is kept as it is; the clip's uncovered part
    /// takes the layer on its own (normal, at its opacity).
    mutating func compositeClipped(_ layer: StyleLayer, clip: PixelBuffer) throws {
        let c = Self.channels, clipData = clip.components, src = layer.source.components
        var data = components, opaque = data
        for o in stride(from: 0, to: data.count, by: c) {
            let alpha = data[o + 3]
            for k in 0..<3 {
                let straight = alpha > 0 ? data[o + k] / alpha : 0
                opaque[o + k] = straight.isFinite ? straight : 0
            }
            opaque[o + 3] = 1
        }
        var onto = PixelBuffer(checkedWidth: width, height: height, storage: opaque)
        try onto.composite(layer.source, x: 0, y: 0, mode: layer.mode, opacity: layer.opacity)
        let blended = onto.components
        for o in stride(from: 0, to: data.count, by: c) {
            let alpha = data[o + 3], inside = min(max(clipData[o + 3], 0), 1)
            guard inside > 0 else { continue }
            let covered = min(alpha, inside), hole = max(inside - alpha, 0) * layer.opacity
            for k in 0..<3 {
                let kept: Float = (alpha - covered) * opaque[o + k]
                data[o + k] = covered * blended[o + k] + kept + hole * src[o + k]
            }
            data[o + 3] = alpha + hole * src[o + 3]
            guard (o..<(o + c)).allSatisfy({ data[$0].isFinite }) else {
                throw RasterError.invalid("clipped style layer: result overflows")
            }
        }
        self = PixelBuffer(checkedWidth: width, height: height, storage: data)
    }
}
