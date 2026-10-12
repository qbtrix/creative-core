// Support.swift: shared CoreRaster test helpers. A seedable RNG (SplitMix64,
// the same algorithm as FlareCoreTests' copy; test targets cannot share files)
// so property and fuzz tests are reproducible.

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
