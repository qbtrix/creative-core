// ParitySamples.swift: deterministic, stably named inputs per op (goldens are
// filed under the names), including the edge cases GPUs get wrong, and how to render one.
import CoreColor
import CoreRaster

/// SplitMix64: the same seed gives the same sequence on every platform.
public struct ParityRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    /// A generator whose sequence depends only on `seed`.
    public init(seed: UInt64) { state = seed }
    /// The next 64 random bits; advances the state.
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// One `RenderBackend` call with its parameters.
public enum ParityCall: Equatable, Sendable {
    /// `display` in the color space, read back as a buffer.
    case display(ColorSpace)
    /// `rotated` by the quarter turn.
    case rotated(QuarterTurn)
    /// `gaussianBlur` with `sigma` in pixels.
    case gaussianBlur(sigma: Double)
    /// `adjusted` by the tone adjustment.
    case adjusted(ToneAdjustment)
    /// `composite` of the source onto the backdrop with its top-left at pixel
    /// (`x`, `y`) of the backdrop, `opacity` from 0 to 1.
    case composite(x: Int, y: Int, mode: BlendMode, opacity: Float)
    /// `resampled` to `width` x `height` pixels.
    case resampled(width: Int, height: Int, filter: ResampleFilter)
    /// `cloned`: each masked pixel takes the pixel `dx`, `dy` pixels away in
    /// the same surface.
    case cloned(dx: Int, dy: Int, mask: Mask)
    /// `transformed` through the matrix into `width` x `height` pixels.
    case transformed(AffineMatrix, width: Int, height: Int, filter: ResampleFilter)
    /// `flipped` across the axis.
    case flipped(FlipAxis)
    /// `composite` of the source onto the backdrop through the matrix (source to backdrop
    /// pixels), `opacity` from 0 to 1.
    case compositeThrough(AffineMatrix, mode: BlendMode, opacity: Float, filter: ResampleFilter)
    /// `applying` each effect in turn, first to last, as a layer's effect stack; never empty.
    case applied([LayerEffect])
}

/// One named input for one op; `backdrop` is set for `.composite` and `.compositeThrough` only.
public struct ParitySample: Equatable, Sendable {
    /// Stable name, unique within the op; goldens are filed under it.
    public let name: String
    /// The backend call to make.
    public let call: ParityCall
    /// The input surface's pixels.
    public let source: PixelBuffer
    /// The surface `composite` draws onto; nil for every other call.
    public let backdrop: PixelBuffer?

    /// A sample named `name` that makes `call` on `source` (onto `backdrop` for `.composite`).
    public init(name: String, call: ParityCall, source: PixelBuffer, backdrop: PixelBuffer?) {
        (self.name, self.call, self.source, self.backdrop) = (name, call, source, backdrop)
    }
}

extension ParityHarness {
    /// Every sample for `op`: alpha 0 with color left in the channels, subnormal
    /// alpha, opaque rows and, when one image is placed in another, a source off each edge.
    public static func sampleSet(for op: RenderOp) throws -> [ParitySample] {
        try RenderError.mapping {
            let alphas: [Float?] = [nil, 0, 1e-45, nil]
            let sources = try zip(["random", "alpha-zero", "alpha-subnormal", "opaque-rows"], 0...).map { name, i in
                (name, try seeded(9, 7, seed: 0x9A21 + UInt64(i), alpha: alphas[i], opaqueRows: i == 3))
            }
            let random = sources[0].1, backdrop = try seeded(11, 8, seed: 0xBAC0, alpha: nil, opaqueRows: true)
            // Position in the 11x8 backdrop, or clone offset, off each edge.
            let edges = [("off-left", -5, 1), ("off-top", 1, -4), ("off-right", 7, 1), ("off-bottom", 1, 6)]
            let over = { (name: String, source: PixelBuffer, x: Int, y: Int, mode: BlendMode) in
                ParitySample(name: name, call: .composite(x: x, y: y, mode: mode, opacity: 0.8), source: source,
                             backdrop: backdrop)
            }
            let place = { (mode: BlendMode) -> [ParitySample] in
                sources.map { over($0.0, $0.1, 1, 1, mode) } + edges.map { over($0.0, random, $0.1, $0.2, mode) }
            }
            let each = { (call: ParityCall) in
                sources.map { ParitySample(name: $0.0, call: call, source: $0.1, backdrop: nil) }
            }
            switch op {
            case .display: return each(.display(.sRGB))
            case .composite: return place(.normal)
            case .blendSeparable, .blendNonSeparable:
                let nonSeparable: Set<BlendMode> = [.hue, .saturation, .color, .luminosity]
                let modes = BlendMode.allCases.filter { $0 != .normal && nonSeparable.contains($0) == (op == .blendNonSeparable) }
                return place(modes.first ?? .normal) + modes.map { over("mode-\($0.rawValue)", random, 1, 1, $0) }
            case .transform: return each(.rotated(.degrees90))
            case .resample: return each(.resampled(width: 13, height: 5, filter: .lanczos3))
            case .blur: return each(.gaussianBlur(sigma: 1.5))
            case .adjust: return each(.adjusted(.contrast(40)))
            case .retouch:
                let mask = try Mask.rectangle(width: 9, height: 7, x: 2.5, y: 1.25, w: 4.5, h: 3.5)
                return each(.cloned(dx: 1, dy: 1, mask: mask)) + edges.map {
                    ParitySample(name: $0.0, call: .cloned(dx: $0.1, dy: $0.2, mask: mask), source: random, backdrop: nil)
                }
            // One file per W1 family (Samples+<Family>.swift), empty until its feature fills it.
            case .maskedComposite: return try MaskedCompositeSamples.all
            case .affine: return try AffineSamples.all
            case .effect: return try EffectSamples.all
            case .color: return try ColorSamples.all
            }
        }
    }

    /// `sample` rendered on `backend` and read back, its surfaces released. A `.composite` or
    /// `.compositeThrough` sample without a backdrop throws `RenderError.raster` naming it.
    public static func render(_ sample: ParitySample, on backend: any RenderBackend) throws -> PixelBuffer {
        let s = try backend.surface(sample.source)
        defer { backend.release(s) }
        let out: RenderSurface
        switch sample.call {
        case .display(let space):
            let bytes = try backend.display(s, colorSpace: space)
            return try RenderError.mapping { try PixelBuffer(rgba8: bytes, width: s.width, height: s.height, colorSpace: space) }
        case let .composite(x, y, mode, opacity):
            out = try onto(sample, on: backend) { try backend.composite(s, onto: &$0, x: x, y: y, mode: mode, opacity: opacity) }
        case let .compositeThrough(m, mode, opacity, filter):
            out = try onto(sample, on: backend) {
                try backend.composite(s, onto: &$0, through: m, mode: mode, opacity: opacity, filter: filter)
            }
        case .rotated(let turn): out = try backend.rotated(s, turn)
        case let .resampled(w, h, filter): out = try backend.resampled(s, width: w, height: h, filter: filter)
        case .gaussianBlur(let sigma): out = try backend.gaussianBlur(s, sigma: sigma)
        case .adjusted(let adjustment): out = try backend.adjusted(s, adjustment)
        case let .cloned(dx, dy, mask): out = try backend.cloned(s, offset: (dx: dx, dy: dy), through: mask)
        case let .transformed(m, w, h, filter): out = try backend.transformed(s, m, width: w, height: h, filter: filter)
        case .flipped(let axis): out = try backend.flipped(s, axis)
        case .applied(let effects): out = try applied(effects, to: s, on: backend, sample.name)
        }
        defer { backend.release(out) }
        return try backend.read(out)
    }

    /// `sample`'s backdrop as a surface on `backend` after `draw` blended onto it; the backdrop is
    /// released if `draw` throws. No backdrop throws `RenderError.raster` naming the sample.
    private static func onto(_ sample: ParitySample, on backend: any RenderBackend,
                             _ draw: (inout RenderSurface) throws -> Void) throws -> RenderSurface {
        guard let backdrop = sample.backdrop else {
            throw RenderError.raster("composite sample '\(sample.name)' has no backdrop")
        }
        var target = try backend.surface(backdrop)
        do { try draw(&target) } catch {
            backend.release(target)
            throw error
        }
        return target
    }

    /// `s` with each of `effects` applied in turn on `backend`, every surface in between
    /// released. No effects throws `RenderError.raster` naming the sample.
    private static func applied(_ effects: [LayerEffect], to s: RenderSurface, on backend: any RenderBackend,
                                _ name: String) throws -> RenderSurface {
        guard let first = effects.first else { throw RenderError.raster("effect sample '\(name)' has no effects") }
        var out = try backend.applying(s, first)
        for effect in effects.dropFirst() {
            let next: RenderSurface
            do { next = try backend.applying(out, effect) } catch {
                backend.release(out)
                throw error
            }
            backend.release(out)
            out = next
        }
        return out
    }

    /// Seeded straight colors premultiplied by `alpha` (random when nil; 0 keeps
    /// the color, as a careless op leaves it), alpha 1 on even rows if `opaqueRows`. Internal so
    /// each W1 family's `Samples+<Family>.swift` builds its inputs the same way.
    static func seeded(_ width: Int, _ height: Int, seed: UInt64, alpha: Float?, opaqueRows: Bool) throws -> PixelBuffer {
        var rng = ParityRandom(seed: seed)
        var buffer = try PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let a = opaqueRows && y % 2 == 0 ? 1 : alpha ?? .random(in: 0...1, using: &rng)
                let c = (0..<3).map { _ in Float.random(in: 0...1, using: &rng) * (a == 0 ? 1 : a) }
                try buffer.setPixel(x: x, y: y, RGBA(r: c[0], g: c[1], b: c[2], a: a))
            }
        }
        return buffer
    }
}
