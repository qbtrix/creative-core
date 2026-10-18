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
public struct AffineMatrix: Hashable, Sendable {
    public var a, b, c, d, tx, ty: Double

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

/// One hue band's shift. Each component is in -100...100; 0 changes nothing.
/// The tone ops clamp a value outside that range.
public struct HSLRange: Hashable, Sendable {
    public var hue, saturation, lightness: Float

    public init(hue: Float = 0, saturation: Float = 0, lightness: Float = 0) {
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
    }
}

/// Per-hue-band shifts for the HSL adjustment, one `HSLRange` per band.
/// The default changes nothing.
public struct HSLAdjustment: Hashable, Sendable {
    public var reds, oranges, yellows, greens, aquas, blues, purples, magentas: HSLRange

    public init(reds: HSLRange = HSLRange(), oranges: HSLRange = HSLRange(), yellows: HSLRange = HSLRange(),
                greens: HSLRange = HSLRange(), aquas: HSLRange = HSLRange(), blues: HSLRange = HSLRange(),
                purples: HSLRange = HSLRange(), magentas: HSLRange = HSLRange()) {
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
/// a value outside that range.
public struct GrayMix: Hashable, Sendable {
    public var reds, yellows, greens, cyans, blues, magentas: Float
    public var tint: RGBA?

    public init(reds: Float, yellows: Float, greens: Float, cyans: Float, blues: Float, magentas: Float,
                tint: RGBA? = nil) {
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
/// and the color it maps to.
public struct GradientMapStop: Hashable, Sendable {
    public var offset: Float
    public var color: RGBA

    public init(offset: Float, color: RGBA) {
        self.offset = offset
        self.color = color
    }
}

/// A 3D color lookup table: `size` samples per axis and `table` holding
/// size³ output colors, red index fastest, then green, then blue.
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

/// A non-destructive effect on a layer's pixels. Distances, radii, offsets and
/// widths are in pixels, 0...1,000; angles in degrees. Denoise `strength` and
/// `detail` are 0...1 (strength 0 changes nothing), clarity `amount` is
/// -100...100 (0 changes nothing, negative softens), glow `intensity` is 0...1
/// (0 changes nothing). The effect ops throw on a value outside its range.
public enum LayerEffect: Hashable, Sendable {
    case boxBlur(radius: Double), motionBlur(degrees: Double, distance: Double), denoise(strength: Double, detail: Double)
    case clarity(amount: Double, radius: Double), glow(color: RGBA, radius: Double, intensity: Double, inner: Bool)
    case shadow(color: RGBA, dx: Double, dy: Double, blur: Double, inner: Bool)
    case stroke(color: RGBA, width: Double, position: StrokePosition)
}

/// Where a stroke effect sits relative to the layer's edge.
public enum StrokePosition: Hashable, Sendable { case outside, inside, center }

/// How close a color must be to the seed for a fill to take it: exactly
/// equal, or within a distance in 0...1 in OKLab.
public enum FillTolerance: Hashable, Sendable {
    case exact
    case within(Float)
}

/// The shape of a raster gradient fill.
public enum RasterGradientShape: Hashable, Sendable { case linear, radial, angle, reflected, diamond }
