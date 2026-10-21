// BlendMode.swift: the blend modes of W3C Compositing and Blending Level 1,
// each the spec's B(Cb, Cs) on straight-alpha colors (Cb backdrop, Cs source).
// Separable modes act on each channel alone; hue, saturation, color and
// luminosity use the spec's Lum, Sat, SetLum, SetSat and ClipColor. Linear
// dodge and linear burn, which the spec does not define, are the separable
// min(1, Cb + Cs) and max(0, Cb + Cs - 1); they come last so the order of the
// spec's modes stays put. Only r, g and b are blended; alpha is Composite.swift's job.

/// How a source color mixes with the backdrop color under it.
public enum BlendMode: String, CaseIterable, Codable, Hashable, Sendable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn
    case hardLight, softLight, difference, exclusion
    case hue, saturation, color, luminosity
    case linearDodge, linearBurn

    /// B(Cb, Cs) for straight-alpha colors. The result carries the source's alpha.
    func blend(backdrop b: RGBA, source s: RGBA) -> RGBA {
        switch self {
        case .normal: return s
        case .multiply: return perChannel(b, s) { cb, cs in cb * cs }
        case .screen: return perChannel(b, s, Self.screen)
        case .overlay: return perChannel(b, s) { cb, cs in Self.hardLight(cs, cb) }
        case .darken: return perChannel(b, s) { cb, cs in min(cb, cs) }
        case .lighten: return perChannel(b, s) { cb, cs in max(cb, cs) }
        case .colorDodge: return perChannel(b, s) { cb, cs in
            if cb == 0 { return 0 }
            if cs >= 1 { return 1 }
            return min(1, cb / (1 - cs))
        }
        case .colorBurn: return perChannel(b, s) { cb, cs in
            if cb >= 1 { return 1 }
            if cs <= 0 { return 0 }
            return 1 - min(1, (1 - cb) / cs)
        }
        case .hardLight: return perChannel(b, s, Self.hardLight)
        case .softLight: return perChannel(b, s) { cb, cs in
            if cs <= 0.5 { return cb - (1 - 2 * cs) * cb * (1 - cb) }
            let d = cb <= 0.25 ? ((16 * cb - 12) * cb + 4) * cb : cb.squareRoot()
            return cb + (2 * cs - 1) * (d - cb)
        }
        case .difference: return perChannel(b, s) { cb, cs in abs(cb - cs) }
        case .exclusion: return perChannel(b, s) { cb, cs in cb + cs - 2 * cb * cs }
        case .hue: return Self.setLum(Self.setSat(s, Self.sat(b)), Self.lum(b))
        case .saturation: return Self.setLum(Self.setSat(b, Self.sat(s)), Self.lum(b))
        case .color: return Self.setLum(s, Self.lum(b))
        case .luminosity: return Self.setLum(b, Self.lum(s))
        case .linearDodge: return perChannel(b, s) { cb, cs in min(1, cb + cs) }
        case .linearBurn: return perChannel(b, s) { cb, cs in max(0, cb + cs - 1) }
        }
    }

    private func perChannel(_ b: RGBA, _ s: RGBA, _ f: (Float, Float) -> Float) -> RGBA {
        RGBA(r: f(b.r, s.r), g: f(b.g, s.g), b: f(b.b, s.b), a: s.a)
    }

    private static func screen(_ cb: Float, _ cs: Float) -> Float {
        cb + cs - cb * cs
    }

    private static func hardLight(_ cb: Float, _ cs: Float) -> Float {
        cs <= 0.5 ? cb * 2 * cs : screen(cb, 2 * cs - 1)
    }

    private static func lum(_ c: RGBA) -> Float {
        0.3 * c.r + 0.59 * c.g + 0.11 * c.b
    }

    private static func sat(_ c: RGBA) -> Float {
        max(c.r, c.g, c.b) - min(c.r, c.g, c.b)
    }

    private static func setLum(_ c: RGBA, _ l: Float) -> RGBA {
        let d = l - lum(c)
        return clipColor(RGBA(r: c.r + d, g: c.g + d, b: c.b + d, a: c.a))
    }

    /// Pulls a color whose channels left 0...1 back in, keeping its luminosity.
    /// The spec divides by L - n and x - L; those are zero only for a gray,
    /// which is skipped so out-of-range grays don't produce NaN.
    private static func clipColor(_ c: RGBA) -> RGBA {
        let l = lum(c)
        let n = min(c.r, c.g, c.b)
        let x = max(c.r, c.g, c.b)
        var out = c
        if n < 0, l > n {
            out = mapRGB(out) { l + (($0 - l) * l) / (l - n) }
        }
        if x > 1, x > l {
            out = mapRGB(out) { l + (($0 - l) * (1 - l)) / (x - l) }
        }
        return out
    }

    /// The spec's SetSat: the max channel becomes `s`, the min 0, the middle
    /// one keeps its relative place; a gray becomes black.
    private static func setSat(_ c: RGBA, _ s: Float) -> RGBA {
        let n = min(c.r, c.g, c.b)
        let x = max(c.r, c.g, c.b)
        guard x > n else { return RGBA(r: 0, g: 0, b: 0, a: c.a) }
        return mapRGB(c) { ($0 - n) * s / (x - n) }
    }

    private static func mapRGB(_ c: RGBA, _ f: (Float) -> Float) -> RGBA {
        RGBA(r: f(c.r), g: f(c.g), b: f(c.b), a: c.a)
    }
}
