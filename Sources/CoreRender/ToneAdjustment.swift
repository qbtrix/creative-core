// ToneAdjustment.swift: the tone adjustments `RenderBackend.adjusted` takes,
// one case per CoreRaster `PixelBuffer` adjustment method, with the labels,
// types and defaults of that method, so `CPUBackend` maps
// each case to its call with no conversion and the Metal backend has the same
// parameters to match. Units are CoreRaster's; parameter checks stay in CoreRaster.
// Each case belongs to one family (`family`), which gates it: the six cases
// from before W1 are `.adjust`, the W1 colour cases are `.color` (CPU first).
import CoreRaster

/// One tone adjustment, as CoreRaster's `Adjustments.swift` defines it.
public enum ToneAdjustment: Equatable, Sendable {
    /// `PixelBuffer.exposure(stops:)`: multiplies every linear color value by
    /// 2^`stops`.
    case exposure(stops: Float)
    /// `PixelBuffer.levels(inBlack:inWhite:gamma:outBlack:outWhite:encoding:)`:
    /// values at or below `inBlack` become `outBlack`, `inWhite` becomes
    /// `outWhite`, with `gamma` (over 1 brightens) between; values above
    /// `inWhite` are not clipped. Linear values, or sRGB-encoded ones with
    /// `.sRGB`, nominally 0 to 1; `inBlack` must be below `inWhite`, `gamma`
    /// above 0.
    case levels(inBlack: Float, inWhite: Float, gamma: Float,
                outBlack: Float, outWhite: Float, encoding: ToneEncoding = .linear)
    /// `PixelBuffer.curves(points:encoding:)`: a monotone cubic through
    /// `points`, applied to each color channel. At least two points, x in 0...1
    /// and strictly increasing; linear values, or sRGB-encoded with `.sRGB`.
    case curves(points: [CurvePoint], encoding: ToneEncoding = .linear)
    /// `PixelBuffer.whiteBalance(temperature:tint:)`: per-channel gains on
    /// linear color. A positive `temperature` warms (red up, blue down); a
    /// positive `tint` pushes toward magenta. Develop sliders, -100...100.
    case whiteBalance(temperature: Float, tint: Float)
    /// `PixelBuffer.contrast(_:)`: an S curve about mid grey (0.18); positive
    /// pushes values away from it, negative pulls them in. -100...100.
    case contrast(Float)
    /// `PixelBuffer.highlightsShadows(highlights:shadows:)`: up to one stop of
    /// exposure at 100, weighted by luminance above mid grey (`highlights`) or
    /// below 0.5 (`shadows`). Both -100...100.
    case highlightsShadows(highlights: Float, shadows: Float)

    // The W1 colour family (`.color`), one case per CoreRaster op the
    // `tone-pack` feature adds. Ranges are that op's: vibrance, hueSaturation,
    // posterize, threshold and gradientMap throw outside them; hsl,
    // blackAndWhite, channelMixer and colorBalance clamp (a non-finite value
    // throws everywhere).
    /// `PixelBuffer.vibrance(_:)`: a saturation boost that moves muted colours
    /// most; negative desaturates. -100...100.
    case vibrance(Float)
    /// `PixelBuffer.hueSaturation(hue:saturation:lightness:)`: `hue` in
    /// degrees -180...180, `saturation` and `lightness` -100...100; throws
    /// outside them.
    case hueSaturation(hue: Float, saturation: Float, lightness: Float)
    /// `PixelBuffer.hsl(_:)`: per-hue-band hue, saturation and lightness
    /// shifts, each percent clamped to -100...100 (hue 100 is +30°).
    case hsl(HSLAdjustment)
    /// `PixelBuffer.blackAndWhite(_:)`: a gray mixed from the hue bands, tinted;
    /// band weights in percent, clamped to -200...300.
    case blackAndWhite(GrayMix)
    /// `PixelBuffer.channelMixer(_:)`: each channel a weighted sum plus a
    /// constant; weights clamped to -2...2, the constant to -1...1.
    case channelMixer(ChannelMatrix)
    /// `PixelBuffer.colorBalance(_:)`: shadow, midtone and highlight shifts,
    /// each component clamped to -100...100.
    case colorBalance(ToneBalance)
    /// `PixelBuffer.gradientMap(_:)`: Rec. 709 luma of the sRGB-encoded (not
    /// linear) straight colour, 0...1, through 2...64 stops, sorted by offset.
    case gradientMap([GradientMapStop])
    /// `PixelBuffer.applying(_:)` of a `ColorLUT`: a trilinear 3D lookup.
    case lut(ColorLUT)
    /// `PixelBuffer.posterized(levels:)`: each channel in `levels` steps, 2...255.
    case posterize(levels: Int)
    /// `PixelBuffer.thresholded(_:)`: white where the Rec. 709 luma of the
    /// sRGB-encoded (not linear) straight colour is at least the level
    /// (0...1), black below.
    case threshold(Float)
    /// `PixelBuffer.inverted()`: each colour channel becomes 1 minus itself.
    case invert
}

extension ToneAdjustment {
    /// The family that gates this adjustment: `.adjust` for the six cases
    /// from before W1, `.color` for the W1 colour cases. A backend runs a
    /// case only when it lists the case's family in `supports`.
    public var family: RenderOp {
        switch self {
        case .exposure, .levels, .curves, .whiteBalance, .contrast, .highlightsShadows: return .adjust
        case .vibrance, .hueSaturation, .hsl, .blackAndWhite, .channelMixer, .colorBalance: return .color
        case .gradientMap, .lut, .posterize, .threshold, .invert: return .color
        }
    }
}
