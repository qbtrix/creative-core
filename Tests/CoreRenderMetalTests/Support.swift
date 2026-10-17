// Support.swift: helpers the device-gated suites share: a seeded premultiplied buffer, a backend
// on the default device and the worst Float16 round-trip delta. Compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal

extension PixelBuffer {
    /// A SplitMix64-seeded premultiplied buffer: alpha in [0, 1], every colour at most alpha.
    static func seeded(width: Int, height: Int, seed: UInt64) throws -> PixelBuffer {
        struct SplitMix64: RandomNumberGenerator {
            var state: UInt64
            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }
        var rng = SplitMix64(state: seed)
        var buffer = try PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let a = Float.random(in: 0...1, using: &rng)
                try buffer.setPixel(x: x, y: y, RGBA(
                    r: Float.random(in: 0...a, using: &rng), g: Float.random(in: 0...a, using: &rng),
                    b: Float.random(in: 0...a, using: &rng), a: a))
            }
        }
        return buffer
    }
}

extension MetalBackend {
    /// A backend on the default device (`cacheURL` nil, reserved). Throws `RenderError.deviceLost` without one.
    static func onDefaultDevice() throws -> MetalBackend {
        guard let device = defaultDevice else { throw RenderError.deviceLost("no default device") }
        return try MetalBackend(device: device, cacheURL: nil)
    }

    /// The largest component delta between `read(surface)` and `expected`; Float16 keeps 2^-11 in [0, 1].
    func worstDelta(reading surface: RenderSurface, against expected: PixelBuffer) throws -> Float {
        let got = try read(surface)
        var worst: Float = 0
        for y in 0..<expected.height {
            for x in 0..<expected.width {
                let sent = try expected.pixel(x: x, y: y)
                let back = try got.pixel(x: x, y: y)
                worst = max(worst, abs(sent.r - back.r), abs(sent.g - back.g), abs(sent.b - back.b), abs(sent.a - back.a))
            }
        }
        return worst
    }
}
#endif
