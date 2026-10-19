// W1Values.swift: the value types the beta-80 W1 engines share (masks and
// mattes, tone, layer effects, affine composite, fill), declared once here so
// CoreRender's contract and every feature compile against the same names.
// Values only: the operations that read them live in each feature's own file.
// Invariants a reader must keep: `AffineMatrix.inverse` is nil exactly when the
// matrix has no finite inverse, and a `ColorLUT` always has a size in 2...65
// and size³ finite entries (its only init checks both).

/// A 2D affine transform. A point (x, y) maps to
/// (a·x + c·y + tx, b·x + d·y + ty): `a`, `b` are the first column,
/// `c`, `d` the second, `tx`, `ty` the translation.
/// Coordinates are continuous pixel units with (0, 0) at the top-left corner
/// of the top-left pixel; pixel (x, y) is sampled at its centre
/// (x + 0.5, y + 0.5), as `rotated(degrees:filter:)` and
/// `resized(width:height:filter:)` already do.
public struct AffineMatrix: Hashable, Sendable {
    public var a, b, c, d, tx, ty: Double

    /// The transform with these entries, taken as given; `inverse` is nil
    /// when they make no finite inverse.
    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    /// The transform that leaves every point where it is.
    public static let identity = AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    /// The transform that undoes this one, or nil when the matrix is
    /// singular (determinant zero) or its inverse is not finite.
    public var inverse: AffineMatrix? {
        let det = a * d - b * c
        if det == 0 || !det.isFinite { return nil }
        let inv = AffineMatrix(a: d / det, b: -b / det, c: -c / det, d: a / det,
                               tx: (c * ty - d * tx) / det, ty: (b * tx - a * ty) / det)
        let parts = [inv.a, inv.b, inv.c, inv.d, inv.tx, inv.ty]
        return parts.allSatisfy(\.isFinite) ? inv : nil
    }
}

/// The axis a flip mirrors across: horizontal swaps left and right,
/// vertical swaps top and bottom.
public enum FlipAxis: Hashable, Sendable { case horizontal, vertical }

/// Where existing pixels sit when a canvas grows or shrinks.
public enum CanvasAnchor: Hashable, Sendable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight
}

/// What a mask reads from a source buffer: its alpha, or its luminance.
public enum MatteSource: Hashable, Sendable { case alpha, luminance }

/// One hue band's shift. `hue` is percent of a ±30° turn (100 = +30°), not
/// degrees; saturation and lightness are percent. Each component is in
/// -100...100; 0 changes nothing. The tone ops clamp a value outside that range.
public struct HSLShift: Hashable, Sendable {
    public var hue, saturation, lightness: Float

    public init(hue: Float = 0, saturation: Float = 0, lightness: Float = 0) {
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
    }
}

/// Per-hue-band shifts for the HSL adjustment, one `HSLShift` per band.
/// The default changes nothing.
public struct HSLAdjustment: Hashable, Sendable {
    public var reds, oranges, yellows, greens, aquas, blues, purples, magentas: HSLShift

    public init(reds: HSLShift = HSLShift(), oranges: HSLShift = HSLShift(), yellows: HSLShift = HSLShift(),
                greens: HSLShift = HSLShift(), aquas: HSLShift = HSLShift(), blues: HSLShift = HSLShift(),
                purples: HSLShift = HSLShift(), magentas: HSLShift = HSLShift()) {
        self.reds = reds
        self.oranges = oranges
        self.yellows = yellows
        self.greens = greens
        self.aquas = aquas
        self.blues = blues
        self.purples = purples
        self.magentas = magentas
    }
}

/// The black-and-white mix: how much each hue band contributes to the gray,
/// each in percent, -200...300, and an optional tint laid over the result.
/// The default mix is 40, 60, 40, 60, 20, 80 with no tint. The tone ops clamp
/// a value outside that range. `tint` is a straight-alpha (not premultiplied),
/// sRGB-encoded color, as a color picker gives it; its alpha is the tint's
/// strength in 0...1 (0 leaves the gray untinted, 1 applies it fully).
public struct GrayMix: Hashable, Sendable {
    public var reds, yellows, greens, cyans, blues, magentas: Float
    public var tint: RGBA?

    public init(reds: Float = 40, yellows: Float = 60, greens: Float = 40, cyans: Float = 60, blues: Float = 20,
                magentas: Float = 80, tint: RGBA? = nil) {
        self.reds = reds
        self.yellows = yellows
        self.greens = greens
        self.cyans = cyans
        self.blues = blues
        self.magentas = magentas
        self.tint = tint
    }
}

/// The channel mixer. Each output channel is a vector (r, g, b, constant):
/// out = r·R + g·G + b·B + constant, on linear values in 0...1. The weights are
/// fractions (1 is 100%, each -2...2) and the constant is added in -1...1, so
/// (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0) changes nothing. When `monochrome`
/// is set, `red` alone makes a gray written to all three channels.
public struct ChannelMatrix: Hashable, Sendable {
    public var red, green, blue: SIMD4<Float>
    public var monochrome: Bool

    public init(red: SIMD4<Float>, green: SIMD4<Float>, blue: SIMD4<Float>, monochrome: Bool) {
        self.red = red
        self.green = green
        self.blue = blue
        self.monochrome = monochrome
    }
}

/// The color balance: an (r, g, b) shift for each tone range, each component
/// in -100...100 (positive moves toward that channel, 0 changes nothing), and
/// whether the result keeps each pixel's luminosity. The tone ops clamp a value
/// outside that range.
public struct ToneBalance: Hashable, Sendable {
    public var shadows, midtones, highlights: SIMD3<Float>
    public var preserveLuminosity: Bool

    public init(shadows: SIMD3<Float>, midtones: SIMD3<Float>, highlights: SIMD3<Float>, preserveLuminosity: Bool) {
        self.shadows = shadows
        self.midtones = midtones
        self.highlights = highlights
        self.preserveLuminosity = preserveLuminosity
    }
}

/// One stop of a gradient map: the luminance `offset` in 0...1 it sits at,
/// and the color it maps to. `color` is straight-alpha (not premultiplied),
/// sRGB-encoded RGB in 0...1, the space the map runs in; its alpha is
/// ignored and each pixel keeps its own alpha.
public struct GradientMapStop: Hashable, Sendable {
    public var offset: Float
    public var color: RGBA

    public init(offset: Float, color: RGBA) {
        self.offset = offset
        self.color = color
    }
}

/// A 3D color lookup table: `size` samples per axis and `table` holding
/// size³ output colors, red index fastest, then green, then blue. It is
/// indexed by and holds sRGB-encoded (not linear) straight RGB values in
/// 0...1, as a `.cube` file stores them; alpha is not looked up.
public struct ColorLUT: Hashable, Sendable {
    public let size: Int
    public let table: [SIMD3<Float>]

    /// The sizes a table may have per axis.
    private static let sizes = 2...65

    /// Throws `RasterError.invalid` when `size` is outside 2...65, when
    /// `table` does not hold exactly size³ entries, or when an entry is not finite.
    public init(size: Int, table: [SIMD3<Float>]) throws {
        guard Self.sizes.contains(size) else {
            throw RasterError.invalid("LUT size \(size) is outside \(Self.sizes)")
        }
        let count = size * size * size
        if table.count != count {
            throw RasterError.invalid("LUT of size \(size) needs \(count) entries, got \(table.count)")
        }
        guard table.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw RasterError.invalid("LUT entries must be finite")
        }
        self.size = size
        self.table = table
    }
}

/// A non-destructive effect on a layer's pixels. Radii, distances and widths
/// are 0...1,000 px; shadow `dx` / `dy` are any finite number of pixels (+x
/// right, +y down; negative casts up or left); angles are in degrees. A radius
/// does not mean the same reach everywhere: box blur `radius` is the half-width
/// of each of three box passes, so colour reaches 3 x radius px (sigma about
/// sqrt(r (r + 1))), while glow `radius`, shadow `blur` and clarity `radius`
/// are the total reach (sigma about value / 3). So `.boxBlur(radius: 10)`
/// spreads about 30 px and `.glow(radius: 10)` about 10 px. Denoise `strength` and
/// `detail` are 0...1 (strength 0 changes nothing), clarity `amount` is
/// -100...100 (0 changes nothing, negative softens), glow `intensity` is 0...1
/// (0 changes nothing). The effect ops throw on a value outside its range.
/// Glow, shadow and stroke `color` are linear, premultiplied RGBA like a
/// `PixelBuffer`'s pixels; their alpha is the effect's opacity.
public enum LayerEffect: Hashable, Sendable {
    /// Three box passes of half-width `radius` px each: reach 3 x radius, sigma about sqrt(r (r + 1)).
    case boxBlur(radius: Double)
    /// Averages along `degrees` (0 is +x, 90 is +y) over a centred line `distance` px long.
    case motionBlur(degrees: Double, distance: Double)
    /// An edge-keeping smooth: `strength` and `detail` in 0...1.
    case denoise(strength: Double, detail: Double)
    /// Local contrast by `amount` against a blur whose total reach is `radius` px (sigma radius / 3).
    case clarity(amount: Double, radius: Double)
    /// A glow whose total reach is `radius` px (sigma about radius / 3).
    case glow(color: RGBA, radius: Double, intensity: Double, inner: Bool)
    /// A shadow offset by any finite (`dx`, `dy`) px, +y down, whose blur reaches `blur` px in total (sigma about blur / 3).
    case shadow(color: RGBA, dx: Double, dy: Double, blur: Double, inner: Bool)
    /// A stroke `width` px wide at `position` on the alpha edge.
    case stroke(color: RGBA, width: Double, position: StrokePosition)
}

/// Where a stroke effect sits relative to the layer's edge, the boundary of
/// its alpha >= 0.5 set.
public enum StrokePosition: Hashable, Sendable {
    /// Entirely off the shape (alpha < 0.5), `width` wide, painted under the layer.
    case outside
    /// Entirely on the shape, `width` wide, painted over the layer and clipped to its alpha.
    case inside
    /// Straddles the edge, `width` / 2 each side (`width` in total), painted over the layer.
    case center
}

/// How close a color must be to the seed for a fill to take it: exactly
/// equal, or within a distance in 0...1 in OKLab.
public enum FillTolerance: Hashable, Sendable {
    case exact
    case within(Float)
}

/// The shape of a raster gradient fill: how a pixel centre `p` maps to the
/// parameter `t` from the start point `a` and end point `b`. Every `t` is then
/// clamped to 0...1.
public enum RasterGradientShape: Hashable, Sendable {
    /// `t` is the projection of `p − a` onto `a→b`, over |b − a|²: 0 at `a`, 1 at `b`.
    case linear
    /// `t` is |p − a| / |b − a|: 0 at `a`, 1 on the circle of radius |b − a|.
    case radial
    /// `t` is the angle of `p − a` from the `a→b` direction, as a fraction of
    /// one full turn in 0..<1, turning clockwise on screen (y points down).
    case angle
    /// The linear `t` mirrored at `a`: its absolute value, so both sides of
    /// `a` ramp out to 1 at |b − a|.
    case reflected
    /// The Chebyshev distance in the `a→b` frame: the larger of the absolute
    /// along and across coordinates of `p − a`, each over |b − a|.
    case diamond
}
