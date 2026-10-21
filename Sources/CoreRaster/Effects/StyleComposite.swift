// StyleComposite.swift: a layer style stack drawn over its layer
// (layer-style-engine LE-4). Each enabled entry with opacity above 0 becomes
// one premultiplied light layer (two for a bevel) the buffer's size, and the
// layers go down in a fixed paint order whatever the list order: under the
// layer, drop shadow, outer glow, outside stroke, each knocked out by the
// layer's alpha; then the layer at the fill opacity; then over it, clipped to
// its alpha, gradient overlay, colour overlay, inner glow, inner shadow; then
// the bevel's shadow and highlight (already clipped by `beveled`) and the
// inside (clipped) and centre strokes. Entries of one kind keep their list
// order. Each layer composites with its entry's mode and opacity (a bevel's
// with its own two modes, times the entry's opacity); the fill opacity fades
// only the layer. Shadows and glows reuse the glows' blurred alpha: `spread`
// first grows the shape (or, inner, its complement) by spread x size on the
// distance field, then the blur runs over the rest, so spread 1 is a hard
// edge. A clipped layer composites onto the canvas made opaque, and the result
// is weighted by the canvas alpha inside the clip; where the clip is not yet
// covered (fill opacity under 1) the layer shows on its own, so a clipped
// layer never adds alpha outside the layer's shape and adds none at all where
// the layer is drawn in full. Invariants: no active entry at fill opacity 1
// returns the buffer itself; the result is the buffer's size and finite; a
// NaN, infinite or over-cap value, or an opacity or spread outside 0...1,
// throws `RasterError.invalid`.

/// Where a light layer goes: under the layer, over it clipped to its alpha, or over it as it is.
enum StylePlacement { case under, clipped, over }

/// One premultiplied light layer of an entry, ready to composite.
struct StyleLayer {
    var source: PixelBuffer, mode: BlendMode, opacity: Float, placement: StylePlacement
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
}

extension LayerStyleStack {
    /// The largest reach, so a caller's padding stays a sane allocation.
    static let maxReach = 1_000_000.0

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
    /// (see the file header). Throws `RasterError.invalid` for a fill opacity
    /// or entry opacity outside 0...1, and for an active entry with a NaN,
    /// infinite or over-cap value (spread outside 0...1, blur or size outside
    /// 0...1,000, stroke width outside 0...1,000, a bevel `beveled` refuses).
    public func styled(_ stack: LayerStyleStack) throws -> PixelBuffer {
        guard (0...1).contains(stack.fillOpacity) else {
            throw RasterError.invalid("fill opacity \(stack.fillOpacity): must be a finite value in 0...1")
        }
        for entry in stack.entries where !(0...1).contains(entry.opacity) {
            throw RasterError.invalid("style entry opacity \(entry.opacity): must be a finite value in 0...1")
        }
        let active = stack.entries.enumerated().filter { $0.element.isEnabled && $0.element.opacity > 0 }
            .sorted { ($0.element.op.paintRank, $0.offset) < ($1.element.op.paintRank, $1.offset) }
        guard !active.isEmpty || stack.fillOpacity < 1 else { return self }
        let layers = try active.flatMap { try styleLayers($0.element) }
        var canvas = try PixelBuffer(width: width, height: height)
        for layer in layers where layer.placement == .under {
            try canvas.composite(layer.source, x: 0, y: 0, mode: layer.mode, opacity: layer.opacity)
        }
        try canvas.composite(self, x: 0, y: 0, mode: .normal, opacity: stack.fillOpacity)
        for layer in layers where layer.placement != .under {
            if layer.placement == .clipped {
                try canvas.compositeClipped(layer, clip: self)
            } else {
                try canvas.composite(layer.source, x: 0, y: 0, mode: layer.mode, opacity: layer.opacity)
            }
        }
        return canvas
    }

    /// The entry's light layers, each the buffer's size.
    func styleLayers(_ entry: StyleEntry) throws -> [StyleLayer] {
        func one(_ source: PixelBuffer, _ placement: StylePlacement) -> [StyleLayer] {
            [StyleLayer(source: source, mode: entry.mode, opacity: entry.opacity, placement: placement)]
        }
        switch entry.op {
        case let .dropShadow(color, dx, dy, spread, blur):
            return one(try lightLayer(color, dx, dy, spread, blur, inner: false, effect: "drop shadow"), .under)
        case let .innerShadow(color, dx, dy, spread, blur):
            return one(try lightLayer(color, dx, dy, spread, blur, inner: true, effect: "inner shadow"), .clipped)
        case let .outerGlow(color, spread, size):
            return one(try lightLayer(color, 0, 0, spread, size, inner: false, effect: "outer glow"), .under)
        case let .innerGlow(color, spread, size):
            return one(try lightLayer(color, 0, 0, spread, size, inner: true, effect: "inner glow"), .clipped)
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
    /// unclipped for `compositeClipped`.
    func lightLayer(_ color: RGBA, _ dx: Double, _ dy: Double, _ spread: Double, _ size: Double,
                    inner: Bool, effect: String) throws -> PixelBuffer {
        guard color.isFinite, dx.isFinite, dy.isFinite else {
            throw RasterError.invalid("\(effect) color \(color) at (\(dx), \(dy)): must be finite")
        }
        guard (0...1).contains(spread) else { throw RasterError.invalid("\(effect) spread \(spread): must be finite and in 0...1") }
        guard size.isFinite, size >= 0, size <= Self.maxLightReach else {
            throw RasterError.invalid("\(effect) size \(size): must be finite and in 0...\(Int(Self.maxLightReach))")
        }
        let choke = spread * size, blur = size - choke
        let work = Self.lightWork(effect: effect, reachName: "size", reach: blur, dx: dx, dy: dy)
        let mask = try spreadAlpha(choke: choke, inner: inner)
            .blurredAlpha(reach: blur, inner: inner, pad: work.pad, cause: work.cause, remedy: work.remedy)
        let src = components, c = Self.channels, paint = [color.r, color.g, color.b, color.a]
        var out = [Float](repeating: 0, count: src.count)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * c
                var cover = Float(mask.sample(Double(x) - dx, Double(y) - dy))
                if !inner { cover *= 1 - min(max(src[o + 3], 0), 1) }
                guard cover > 0 else { continue }
                for k in 0..<c { out[o + k] = paint[k] * cover }
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
        guard strokeWidth.isFinite, strokeWidth >= 0, strokeWidth <= Self.maxStrokeWidth else {
            throw RasterError.invalid("stroke width \(strokeWidth): must be finite and in 0...\(Int(Self.maxStrokeWidth))")
        }
        let paint = try fillLayer(fill)
        guard strokeWidth > 0 else { return try PixelBuffer(width: width, height: height) }
        let distance = try edgeDistances(), src = components, c = Self.channels
        var out = paint.components
        for i in 0..<(width * height) {
            let o = i * c, alpha = src[o + 3], inShape = alpha >= 0.5
            let cover: Float
            switch position {
            case .outside: cover = (inShape ? 1 : Self.coverage(edge: distance[i], width: strokeWidth)) * (1 - min(max(alpha, 0), 1))
            case .inside: cover = inShape ? Self.coverage(edge: distance[i], width: strokeWidth) : 1
            case .center: cover = Self.coverage(edge: distance[i], width: strokeWidth / 2)
            }
            for k in 0..<c { out[o + k] *= cover }
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: out)
    }

    /// `fill` over the whole buffer: a colour flood, or `RasterGradient`'s
    /// ramp in this buffer's pixel space.
    func fillLayer(_ fill: StyleFill) throws -> PixelBuffer {
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
