// Support.swift: shared CoreRaster test helpers. A seedable RNG (SplitMix64,
// the same algorithm as FlareCoreTests' copy; test targets cannot share files)
// so property and fuzz tests are reproducible, a random pixel built from it,
// and the calling thread's CPU time, for budgets that must not count the time
// a parallel test run keeps the thread waiting for a core.
import CoreRaster
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

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

/// The calling thread's clock could not be read.
struct ThreadClockUnavailable: Error {}

/// CPU time the calling thread has used so far (POSIX `CLOCK_THREAD_CPUTIME_ID`).
/// Time spent waiting for a core does not count.
func threadCPUTime() throws -> Duration {
    var now = timespec()
    guard clock_gettime(CLOCK_THREAD_CPUTIME_ID, &now) == 0 else { throw ThreadClockUnavailable() }
    return .seconds(Int64(now.tv_sec)) + .nanoseconds(Int64(now.tv_nsec))
}

/// The thread CPU time `body` takes. `body` is synchronous, so it starts and
/// ends on the thread that reads the clock.
func measureThreadCPUTime(_ body: () throws -> Void) throws -> Duration {
    let start = try threadCPUTime()
    try body()
    return try threadCPUTime() - start
}
