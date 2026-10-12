// Support.swift: shared CoreRaster test helpers. A seedable RNG (SplitMix64,
// the same algorithm as FlareCoreTests' copy; test targets cannot share files)
// so property and fuzz tests are reproducible, and a random pixel and buffer
// built from it.
import CoreRaster

/// SplitMix64: tiny, fast, seedable. Same seed, same sequence, on every platform.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A finite pixel with components in -2...2 and alpha in 0...1.
func randomPixel(_ rng: inout SplitMix64) -> RGBA {
    RGBA(r: .random(in: -2...2, using: &rng), g: .random(in: -2...2, using: &rng),
         b: .random(in: -2...2, using: &rng), a: .random(in: 0...1, using: &rng))
}

/// A buffer of the given size filled with `randomPixel`.
func randomBuffer(width: Int, height: Int, _ rng: inout SplitMix64) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: width, height: height)
    for y in 0..<height {
        for x in 0..<width { try buffer.setPixel(x: x, y: y, randomPixel(&rng)) }
    }
    return buffer
}
