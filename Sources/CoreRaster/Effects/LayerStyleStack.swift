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
    /// Half inside and half outside.
    case emboss
    /// Inside raised and outside sunk, so the edge looks pressed in.
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
    public var shape: BevelShape, technique: BevelTechnique
    /// `depth` 0.01...10 scales the slope; `up: false` sinks the edge instead of raising it;
    /// `size` 0...250 px is how far from the edge the height rises; `soften` 0...16 px blurs it.
    public var depth: Double, up: Bool, size: Double, soften: Double
    /// Degrees: angle 0 is light from +x, 90 from +y (down); altitude 0...90, 90 straight above.
    public var angle: Double, altitude: Double
    /// The lit side's colour, blend mode and opacity 0...1.
    public var highlight: RGBA, highlightMode: BlendMode, highlightOpacity: Float
    /// The side facing away: colour, blend mode and opacity 0...1.
    public var shadow: RGBA, shadowMode: BlendMode, shadowOpacity: Float

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
public enum StyleFill: Hashable, Sendable {
    case color(RGBA)
    /// `RasterGradient`'s ramp from `from` to `to` in the layer's pixels.
    case gradient(stops: [RasterGradientStop], shape: RasterGradientShape, from: Mask.Point, to: Mask.Point)
}

/// One effect of a layer style. Distances are px, +y down; `spread` is 0...1.
public enum StyleOp: Hashable, Sendable {
    case dropShadow(color: RGBA, dx: Double, dy: Double, spread: Double, blur: Double)
    case innerShadow(color: RGBA, dx: Double, dy: Double, spread: Double, blur: Double)
    case outerGlow(color: RGBA, spread: Double, size: Double)
    case innerGlow(color: RGBA, spread: Double, size: Double)
    case stroke(fill: StyleFill, width: Double, position: StrokePosition)
    /// The fill over the layer's alpha (a colour or a gradient overlay).
    case overlay(StyleFill)
    case bevel(Bevel)
}

/// One op in a stack, composited with `mode` at `opacity` 0...1; skipped when not enabled.
public struct StyleEntry: Hashable, Sendable {
    public var op: StyleOp
    public var mode: BlendMode
    public var opacity: Float
    public var isEnabled: Bool

    public init(op: StyleOp, mode: BlendMode = .normal, opacity: Float = 1, isEnabled: Bool = true) {
        (self.op, self.mode, self.opacity, self.isEnabled) = (op, mode, opacity, isEnabled)
    }
}

/// A layer's style: its entries, drawn in the fixed paint order whatever their
/// order here, and the opacity 0...1 of the layer's own pixels (not its effects).
public struct LayerStyleStack: Hashable, Sendable {
    public var entries: [StyleEntry]
    public var fillOpacity: Float

    public init(entries: [StyleEntry], fillOpacity: Float = 1) {
        (self.entries, self.fillOpacity) = (entries, fillOpacity)
    }
}
