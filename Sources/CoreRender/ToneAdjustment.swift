// ToneAdjustment.swift: the tone adjustments `RenderBackend.adjusted` takes,
// one case per CoreRaster `PixelBuffer` adjustment method, with the labels,
// types and defaults of that method, so a CPU backend, as it lands, can map
// each case to its call with no conversion and the Metal backend has the same
// parameters to match. Units are CoreRaster's; parameter checks stay in CoreRaster.
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
}
