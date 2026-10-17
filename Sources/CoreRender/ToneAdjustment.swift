// ToneAdjustment.swift: the tone operations `RenderBackend.adjusted` takes, one
// case per CoreRaster adjustment. The parameters are CoreRaster's, unchanged.

import CoreRaster

/// One tone adjustment, with the parameters CoreRaster takes for it.
public enum ToneAdjustment: Hashable, Sendable {
    case exposure(stops: Float)
    case levels(inBlack: Float, inWhite: Float, gamma: Float,
                outBlack: Float, outWhite: Float, encoding: ToneEncoding)
    case curves(points: [CurvePoint], encoding: ToneEncoding)
    case whiteBalance(temperature: Float, tint: Float)
    case contrast(Float)
    case highlightsShadows(highlights: Float, shadows: Float)
}
