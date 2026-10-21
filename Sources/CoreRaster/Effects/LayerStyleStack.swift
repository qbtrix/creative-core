// LayerStyleStack.swift: the value types of a layer style (layer-style-engine
// LE-1): a bevel's shape, technique and light, a style fill (a colour or a
// gradient in the layer's pixel space), the seven style ops, one entry per op
// with its own blend mode, opacity and switch, and the stack of entries with
// the layer's fill opacity. `styled(_:)` and `reach` (StyleComposite.swift,
// LE-4) draw a stack and measure how far it reaches. Invariants: every type is a Hashable, Sendable value; no
// field is validated here, the ops that read them throw `RasterError.invalid`
// for a NaN, infinite or over-cap value.

/// How a bevel's height rises from the layer's edge.
public enum BevelShape: String, CaseIterable, Codable, Sendable {
    /// Inside the edge, over the layer.
    case innerBevel
    /// Outside the edge, under the layer.
    case outerBevel
    /// Straddles the edge: raised inside, sunk outside.
    case emboss
    /// Low at the edge and rising on both sides, so the edge looks pressed in.
    case pillowEmboss
}

/// The profile of a bevel's height across its `size`.
public enum BevelTechnique: String, CaseIterable, Codable, Sendable {
    /// A rounded profile.
    case smooth
    /// A straight ramp.
    case chiselHard
    /// A straight ramp blurred by 1 px.
    case chiselSoft
}

/// A bevel and emboss: height from the alpha's distance field, lit from
/// `angle` and `altitude`, drawn as a highlight and a shadow layer.
public struct Bevel: Hashable, Sendable {
    /// Where the height rises: inside, outside, straddling or pressed into the edge.
    public var shape: BevelShape
    /// The height's profile across `size`: smooth, chisel hard or chisel soft.
    public var technique: BevelTechnique
    /// `depth` 0.01...10 scales the slope; `up: false` sinks the edge instead of raising it;
    /// `size` 0...250 px is how far from the edge the height rises; `soften` 0...16 px blurs it.
    public var depth: Double, up: Bool, size: Double, soften: Double
    /// Degrees: angle 0 is light from +x, 90 from +y (down); altitude 0...90, 90 straight above.
    /// The angle turns clockwise (y down); a counterclockwise UI angle a is 360 − a.
    public var angle: Double, altitude: Double
    /// The lit side's premultiplied colour, blend mode and opacity 0...1.
    public var highlight: RGBA, highlightMode: BlendMode, highlightOpacity: Float
    /// The side facing away: premultiplied colour, blend mode and opacity 0...1.
    public var shadow: RGBA, shadowMode: BlendMode, shadowOpacity: Float

    /// A bevel with every field given; nothing is validated until `beveled` or `styled` reads it.
    public init(shape: BevelShape, technique: BevelTechnique, depth: Double, up: Bool, size: Double, soften: Double,
                angle: Double, altitude: Double, highlight: RGBA, highlightMode: BlendMode, highlightOpacity: Float,
                shadow: RGBA, shadowMode: BlendMode, shadowOpacity: Float) {
        (self.shape, self.technique, self.depth, self.up, self.size, self.soften) = (shape, technique, depth, up, size, soften)
        (self.angle, self.altitude) = (angle, altitude)
        (self.highlight, self.highlightMode, self.highlightOpacity) = (highlight, highlightMode, highlightOpacity)
        (self.shadow, self.shadowMode, self.shadowOpacity) = (shadow, shadowMode, shadowOpacity)
    }
}

/// A colour or a gradient in the layer's pixel space.
///
/// Every `RGBA` here is linear and premultiplied (r, g, b ≤ a), as `PixelBuffer`
/// stores it; a gradient's stops are straight alpha (`RasterGradientStop`).
public enum StyleFill: Hashable, Sendable {
    /// A flat premultiplied colour over the whole layer.
    case color(RGBA)
    /// `RasterGradient`'s ramp from `from` to `to` in the layer's pixels.
    case gradient(stops: [RasterGradientStop], shape: RasterGradientShape, from: Mask.Point, to: Mask.Point)
}

/// One effect of a layer style. Distances are px, +y down.
///
/// Every `RGBA` here is linear and premultiplied (r, g, b ≤ a), as `PixelBuffer`
/// stores it; a gradient's stops are straight alpha (`RasterGradientStop`).
/// For a shadow or a glow, `blur`/`size` px is the whole extent past the edge
/// (a shadow's offset aside); `spread` 0...1 is the hard fraction of it.
public enum StyleOp: Hashable, Sendable {
    /// The layer's alpha in `color` under the layer, moved by (`dx`, `dy`) px (+dx right, +dy down),
    /// `blur` 0...1,000 px past the edge; knocked out where the layer is.
    case dropShadow(color: RGBA, dx: Double, dy: Double, spread: Double, blur: Double)
    /// `color` inside the layer from the alpha's complement moved by (`dx`, `dy`) px, `blur` 0...1,000 px in
    /// from the edge, clipped to the alpha: +dx darkens the left inside edge, +dy the top one.
    case innerShadow(color: RGBA, dx: Double, dy: Double, spread: Double, blur: Double)
    /// `color` around the layer, `size` 0...1,000 px past the edge, under the layer and knocked out where it is.
    case outerGlow(color: RGBA, spread: Double, size: Double)
    /// `color` inward from the edge, `size` 0...1,000 px deep, clipped to the alpha.
    case innerGlow(color: RGBA, spread: Double, size: Double)
    /// A band `width` 0...1,000 px wide at the edge in `fill`: outside it, inside it, or for `.center`
    /// straddling it, half inside and half outside.
    case stroke(fill: StyleFill, width: Double, position: StrokePosition)
    /// The fill over the layer's alpha (a colour or a gradient overlay).
    case overlay(StyleFill)
    /// A bevel and emboss: a highlight and a shadow layer from `beveled`.
    case bevel(Bevel)
}

/// One op in a stack, composited with `mode` at `opacity` 0...1; skipped when not enabled.
/// For `.bevel`, `mode` is unused; the bevel's `highlightMode` and `shadowMode`
/// apply, each times `opacity`.
public struct StyleEntry: Hashable, Sendable {
    /// The effect this entry draws.
    public var op: StyleOp
    /// How the effect's light layer blends; unused for `.bevel`.
    public var mode: BlendMode
    /// The effect's opacity, 0...1; 0 draws nothing.
    public var opacity: Float
    /// Whether the effect is drawn; a disabled entry is skipped and adds nothing to `reach`.
    public var isEnabled: Bool

    /// An entry drawing `op`, by default Normal, fully opaque and enabled.
    public init(op: StyleOp, mode: BlendMode = .normal, opacity: Float = 1, isEnabled: Bool = true) {
        (self.op, self.mode, self.opacity, self.isEnabled) = (op, mode, opacity, isEnabled)
    }
}

/// A layer's style: its entries, drawn in the fixed paint order whatever their
/// order here, and the opacity 0...1 of the layer's own pixels (not its effects).
public struct LayerStyleStack: Hashable, Sendable {
    /// The effects, drawn in the fixed paint order, not this order; entries of one kind keep this order.
    public var entries: [StyleEntry]
    /// The opacity 0...1 of the layer's own pixels only; its effects keep their opacity.
    public var fillOpacity: Float

    /// A stack of `entries` over the layer at `fillOpacity`, by default 1.
    public init(entries: [StyleEntry], fillOpacity: Float = 1) {
        (self.entries, self.fillOpacity) = (entries, fillOpacity)
    }
}
