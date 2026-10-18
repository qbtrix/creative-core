// LottieExporter+Tracks.swift: animated Lottie properties and keyframes written from layer tracks.

/// A scalar property, animated from one track.
typealias LottieScalar = LottieProperty<Double>

extension LottieProperty where Value == Double {
    /// `at0` is the track's finite value at frame 0, used when it has under two
    /// keyframes. `map` turns a finite track value into the written one.
    init(_ track: [Keyframe], at0: Double, map: (Double) -> Double = { $0 }) throws {
        guard track.count > 1 else {
            self = .fixed(LottieStatic(map(at0)))
            return
        }
        self = .animated(try LottieKeyframe.list(track) { _, key in [map(try LottieExporter.finite(key.value))] })
    }
}

extension LottieProperty where Value == [Double] {
    /// A layer's 2-D scale, times 100, from its `scaleX` and `scaleY` tracks.
    /// `x0` and `y0` are the finite scales at frame 0.
    init(scaleOf layer: Layer, x0: Double, y0: Double, durationFrames: Int) throws {
        let xs = layer.tracks["scaleX"] ?? []
        let ys = layer.tracks["scaleY"] ?? []
        // Checked after the times 100: a finite 1e307 becomes infinity.
        func f(_ v: Double) throws -> Double { try LottieExporter.finite(v * 100) }
        func still() throws -> Self { .fixed(LottieStatic([try f(x0), try f(y0)])) }
        if xs.count <= 1, ys.count <= 1 {
            self = try still()
        } else if ys.count <= 1 {
            let y = try f(y0)
            self = .animated(try LottieKeyframe.list(xs) { _, key in [try f(key.value), y] })
        } else if xs.count <= 1 {
            let x = try f(x0)
            self = .animated(try LottieKeyframe.list(ys) { _, key in [x, try f(key.value)] })
        } else if xs.count == ys.count,
                  zip(xs, ys).allSatisfy({ $0.frame == $1.frame && $0.easing == $1.easing }) {
            self = .animated(try LottieKeyframe.list(xs) { index, key in [try f(key.value), try f(ys[index].value)] })
        } else {
            // Checked before hi: durationFrames - 1 overflows on Int.min.
            guard durationFrames > 0 else {
                self = try still()
                return
            }
            let frames = (xs + ys).map(\.frame)
            let lo = max(0, frames.min() ?? 0)
            let hi = min(durationFrames - 1, frames.max() ?? 0)
            // lo >= 0 keeps hi - lo + 1 in range.
            guard lo <= hi else {
                self = try still()
                return
            }
            guard hi - lo + 1 <= LottieExporter.maxBakedKeys else {
                throw LottieExportError.unsupported("scale track")
            }
            var baked: [LottieKeyframe] = []
            baked.reserveCapacity(hi - lo + 1)
            for frame in lo...hi {
                let s = layer.sample(at: Double(frame))
                let key = LottieKeyframe(t: frame, s: [try f(s["scaleX"] ?? 1), try f(s["scaleY"] ?? 1)])
                baked.append(frame < hi ? key.eased(.linear) : key)
            }
            self = .animated(baked)
        }
    }
}

/// One keyframe of an animated property. The last one carries only `t` and `s`.
struct LottieKeyframe: Encodable, Sendable {
    var t: Int
    var s: [Double]
    var o: LottieEase?
    var i: LottieEase?
    var h: Int?

    /// One keyframe per track key, `value` giving each one's `s` from its index
    /// and key; every keyframe but the last carries its key's easing.
    static func list(_ track: [Keyframe], value: (Int, Keyframe) throws -> [Double]) throws -> [LottieKeyframe] {
        try track.enumerated().map { index, key in
            let out = LottieKeyframe(t: key.frame, s: try value(index, key))
            return index < track.count - 1 ? out.eased(key.easing) : out
        }
    }

    /// This keyframe with `easing` written as `h: 1` for hold or `o`/`i` tangents.
    func eased(_ easing: Easing) -> LottieKeyframe {
        var out = self
        switch easing {
        case .hold:
            out.h = 1
        case .linear:
            out.o = LottieEase(0, 0)
            out.i = LottieEase(1, 1)
        case let .cubicBezier(x1, y1, x2, y2):
            if x1.isFinite, y1.isFinite, x2.isFinite, y2.isFinite {
                out.o = LottieEase(min(max(x1, 0), 1), y1)
                out.i = LottieEase(min(max(x2, 0), 1), y2)
            } else {
                out.o = LottieEase(0, 0)
                out.i = LottieEase(1, 1)
            }
        }
        return out
    }
}

/// An easing tangent: `{"x": [x], "y": [y]}` on the 0...1 progress square.
struct LottieEase: Encodable, Sendable {
    var x: [Double]
    var y: [Double]
    init(_ x: Double, _ y: Double) {
        self.x = [x]
        self.y = [y]
    }
}
