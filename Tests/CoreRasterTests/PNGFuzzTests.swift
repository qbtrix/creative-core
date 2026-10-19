// PNGFuzzTests.swift: seeded mutations of spec-built PNGs (PNGFixtures)
// must throw a CodecError or decode, never trap or hang. Raw mutations
// mostly stop at a chunk CRC, so a second run mutates chunk bodies (IHDR,
// PLTE, tRNS and the zlib stream) and recomputes each CRC to reach the
// header checks, the inflater and the unfilter.
@testable import CoreRaster
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct PNGFuzzTests {
    typealias F = PNGFixtures

    static var seeds: [Data] {
        let palette: [UInt8] = (0..<16).flatMap { (i: Int) -> [UInt8] in [UInt8(i * 16), UInt8(255 - i * 16), UInt8(i)] }
        let indexed = F.png(F.ramp(7, 5, channels: 1, depth: 4), depth: 4, colorType: 3,
                            extra: [F.chunk("PLTE", palette), F.chunk("tRNS", [0, 64, 128])], filter: { $0 % 5 })
        let deep = F.png(F.ramp(9, 9, channels: 4, depth: 16), depth: 16, colorType: 6, interlaced: true, idats: 2, filter: { ($0 + 4) % 5 })
        let bits = F.png(F.ramp(13, 3, channels: 1, depth: 1), depth: 1, colorType: 0, filter: { $0 % 5 })
        return [indexed, deep, bits]
    }

    @Test func thousandMutationsThrowOrDecode() {
        fuzz(mutations(of: Self.seeds, count: 1_000, seed: 0x9E6)) { _ = try PNG.read($0) }
        fuzz(mutations(of: Self.seeds, count: 200, seed: 0x9E7)) { _ = try PNG.info($0) }
    }

    @Test func crcFixedMutations() {
        var rng = SplitMix64(seed: 0x9E8)
        let cases = (0..<1_000).map { i -> Data in
            var parts = F.chunks(Self.seeds[i % 3])
            let at = Int.random(in: 0..<(parts.count - 1), using: &rng)  // never IEND
            let body = mutations(of: [Data(parts[at].body)], count: 1, seed: rng.next()).first ?? Data()
            parts[at].body = [UInt8](body)
            return Data(F.signature + parts.flatMap { F.chunk($0.type, $0.body) })
        }
        fuzz(cases) { _ = try PNG.read($0) }
    }
}
