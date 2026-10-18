// CPUBackend+Ops.swift: the CPU backend's transform, resample, blur, adjust and
// retouch families (render-backend RB-4). Each op is exactly the CoreRaster
// `PixelBuffer` method it names, with its arguments passed through in order, so
// its pixels equal the direct call with `==`. A `.color` tone adjustment goes
// to `colorAdjusted` (CPUBackend+Color.swift), and `notBuilt` is the answer
// of each W1 family's stub file until its feature fills it.
// Invariants: each op reads `s` gated by its family (a tone adjustment by
// `adjustment.family`) and returns a new surface, leaving `s` unchanged
// (`derived`); every CoreRaster error comes back as `RenderError.raster` with
// the same message; each `.adjust` case maps to the method of the same name
// with every parameter, encoding included.
import CoreRaster

extension CPUBackend {
    public func cropped(_ s: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface {
        try derived(s, .transform) { try $0.cropped(x: x, y: y, width: width, height: height) }
    }

    public func rotated(_ s: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface {
        try derived(s, .transform) { $0.rotated(turn) }
    }

    public func resampled(_ s: RenderSurface, width: Int, height: Int, filter: ResampleFilter) throws -> RenderSurface {
        try derived(s, .resample) { try $0.resized(width: width, height: height, filter: filter) }
    }

    public func gaussianBlur(_ s: RenderSurface, sigma: Double) throws -> RenderSurface {
        try derived(s, .blur) { try $0.gaussianBlur(sigma: sigma) }
    }

    public func unsharpMask(_ s: RenderSurface, amount: Double, sigma: Double, threshold: Double) throws -> RenderSurface {
        try derived(s, .blur) { try $0.unsharpMask(amount: amount, sigma: sigma, threshold: threshold) }
    }

    public func adjusted(_ s: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface {
        try derived(s, adjustment.family) { buffer in
            switch adjustment {
            case .exposure(let stops):
                try buffer.exposure(stops: stops)
            case let .levels(inBlack, inWhite, gamma, outBlack, outWhite, encoding):
                try buffer.levels(inBlack: inBlack, inWhite: inWhite, gamma: gamma,
                                  outBlack: outBlack, outWhite: outWhite, encoding: encoding)
            case let .curves(points, encoding):
                try buffer.curves(points: points, encoding: encoding)
            case let .whiteBalance(temperature, tint):
                try buffer.whiteBalance(temperature: temperature, tint: tint)
            case .contrast(let amount):
                try buffer.contrast(amount)
            case let .highlightsShadows(highlights, shadows):
                try buffer.highlightsShadows(highlights: highlights, shadows: shadows)
            case .vibrance, .hueSaturation, .hsl, .blackAndWhite, .channelMixer, .colorBalance,
                 .gradientMap, .lut, .posterize, .threshold, .invert:
                try colorAdjusted(buffer, adjustment)  // CPUBackend+Color.swift
            }
        }
    }

    public func cloned(_ s: RenderSurface, offset: (dx: Int, dy: Int), through mask: Mask) throws -> RenderSurface {
        try derived(s, .retouch) { try $0.cloned(offset: offset, through: mask) }
    }

    /// The answer of a W1 op its feature has not filled yet: `s` checked as
    /// `derived` checks it (`op`'s gate, then the surface), then
    /// `unsupported(op)`. Each `CPUBackend+<Family>.swift` stub calls it.
    func notBuilt(_ s: RenderSurface, _ op: RenderOp) throws -> RenderSurface {
        try derived(s, op) { _ in throw RenderError.unsupported(op) }
    }
}
