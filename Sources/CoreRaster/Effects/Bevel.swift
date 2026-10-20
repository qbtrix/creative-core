// Bevel.swift: bevel and emboss (layer-style-engine LE-3). The signed
// distance to the alpha edge (`DistanceField`, half a pixel in from the
// centre-to-centre distance so the edge sits between pixels) becomes a height
// across `size`: inner bevel rises inward from the edge, outer bevel rises
// toward it from `size` outside, emboss straddles it, pillow emboss rises
// both ways from it (a groove). The height runs 0...1 through the technique's
// profile (smooth 1 - (1 - t)^2, chisel hard t, chisel soft t blurred 1 px),
// is negated when not `up`, and box blurred by `soften` (FX-3's
// `boxBlurred(radius: reach / 3)`, the glows' convention). Its normal from
// central differences, slope scaled by `depth`, is lit from `angle` (0 is +x,
// 90 is +y, down) and `altitude`: the lean of the normal toward the light,
// n.xy . l.xy, is the highlight where positive and the shadow where negative.
// That is Lambert's n . l less the flat term n.z l.z, so a flat top casts
// nothing and an overhead light (altitude 90) casts no shadow.
// Invariants: both layers are the buffer's size, each pixel the layer's
// premultiplied colour times coverage times opacity; size 0 paints nothing;
// an inner bevel is clipped to the alpha, an outer one to its complement, and
// nothing is painted past `size` outside the edge; a NaN, infinite or
// out-of-range parameter throws `RasterError.invalid`.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

extension PixelBuffer {
    /// The bevel's two light layers, each the buffer's size: where the edge faces the light, and where it faces away.
    /// Throws `RasterError.invalid` for a depth outside 0.01...10, a size outside 0...250, a soften outside 0...16,
    /// an angle that is not finite, an altitude outside 0...90, an opacity outside 0...1 or a colour that is not finite.
    public func beveled(_ bevel: Bevel) throws -> (highlight: PixelBuffer, shadow: PixelBuffer) {
        try Self.check(bevel)
        let empty = try PixelBuffer(width: width, height: height)
        guard bevel.size > 0 else { return (empty, empty) }
        let field = try DistanceField(alpha: self)
        let size = bevel.size, n = width * height, c = Self.channels
        var signed = [Double](repeating: 0, count: n)
        var heights = [Float](repeating: 0, count: n * c)
        for y in 0..<height {
            for x in 0..<width {
                let inside = Double(field.inside(x: x, y: y)), i = y * width + x
                let d = inside > 0 ? inside - 0.5 : 0.5 - Double(field.outside(x: x, y: y))
                signed[i] = d
                let h = Self.profile(Self.rise(d / size, bevel.shape), bevel.technique)
                heights[i * c] = Float(bevel.up ? h : -h)
            }
        }
        var lifted = PixelBuffer(checkedWidth: width, height: height, storage: heights)
        if bevel.technique == .chiselSoft { lifted = try lifted.boxBlurred(radius: 1.0 / 3) }
        lifted = try lifted.boxBlurred(radius: bevel.soften / 3)
        let h = lifted.components, src = components
        let theta = bevel.angle * .pi / 180, alt = bevel.altitude * .pi / 180
        // Snap the rounding residue at right angles to 0, so an overhead light leans nowhere.
        let cosA = abs(cos(alt)) < 1e-12 ? 0 : cos(alt)
        let lx = cosA * cos(theta), ly = cosA * sin(theta)
        let slope = bevel.depth * size
        var highlight = empty.components, shadow = empty.components
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x, alpha = Double(min(max(src[i * c + 3], 0), 1))
                guard signed[i] >= -size else { continue }
                let clip: Double
                switch bevel.shape {
                case .innerBevel: clip = alpha
                case .outerBevel: clip = 1 - alpha
                case .emboss, .pillowEmboss: clip = 1
                }
                guard clip > 0 else { continue }
                func at(_ qx: Int, _ qy: Int) -> Double {
                    Double(h[(min(max(qy, 0), height - 1) * width + min(max(qx, 0), width - 1)) * c])
                }
                let nx = -(at(x + 1, y) - at(x - 1, y)) / 2 * slope, ny = -(at(x, y + 1) - at(x, y - 1)) / 2 * slope
                let lean = (nx * lx + ny * ly) / (nx * nx + ny * ny + 1).squareRoot()
                let cover = Float(min(abs(lean), 1) * clip)
                guard cover > 0 else { continue }
                let (paint, opacity) = lean > 0 ? (bevel.highlight, bevel.highlightOpacity) : (bevel.shadow, bevel.shadowOpacity)
                let k = cover * opacity, o = i * c
                let px = [paint.r * k, paint.g * k, paint.b * k, paint.a * k]
                if lean > 0 { highlight.replaceSubrange(o..<(o + c), with: px) } else { shadow.replaceSubrange(o..<(o + c), with: px) }
            }
        }
        return (PixelBuffer(checkedWidth: width, height: height, storage: highlight),
                PixelBuffer(checkedWidth: width, height: height, storage: shadow))
    }

    /// Where 0...1 a pixel `t` sizes from the edge (+ inside, − outside) sits on `shape`'s rise, clamped to 0...1.
    static func rise(_ t: Double, _ shape: BevelShape) -> Double {
        let r: Double
        switch shape {
        case .innerBevel: r = t
        case .outerBevel: r = 1 + t
        case .emboss: r = 0.5 + t
        case .pillowEmboss: r = 2 * abs(t)
        }
        return min(max(r, 0), 1)
    }

    /// The height at rise `r` 0...1: rounded for smooth, a straight ramp for either chisel.
    static func profile(_ r: Double, _ technique: BevelTechnique) -> Double {
        technique == .smooth ? 1 - (1 - r) * (1 - r) : r
    }

    /// Throws `RasterError.invalid` naming the first of `bevel`'s parameters that is NaN, infinite or out of range.
    static func check(_ bevel: Bevel) throws {
        let ranges: [(String, Double, ClosedRange<Double>)] = [
            ("depth", bevel.depth, 0.01...10), ("size", bevel.size, 0...250), ("soften", bevel.soften, 0...16),
            ("altitude", bevel.altitude, 0...90), ("highlight opacity", Double(bevel.highlightOpacity), 0...1),
            ("shadow opacity", Double(bevel.shadowOpacity), 0...1),
        ]
        for (name, value, range) in ranges where !(value.isFinite && range.contains(value)) {
            throw RasterError.invalid("bevel \(name) \(value): must be finite and in \(range.lowerBound)...\(range.upperBound)")
        }
        guard bevel.angle.isFinite else { throw RasterError.invalid("bevel angle \(bevel.angle): must be finite") }
        guard bevel.highlight.isFinite, bevel.shadow.isFinite else {
            throw RasterError.invalid("bevel colours \(bevel.highlight), \(bevel.shadow): must be finite")
        }
    }
}
