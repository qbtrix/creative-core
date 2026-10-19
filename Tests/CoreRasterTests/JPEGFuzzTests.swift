// JPEGFuzzTests.swift: seeded mutations of spec-built JPEGs (JPEGFixtures)
// must throw a CodecError or decode, never trap or hang; a second run damages
// only the entropy-coded bytes so the headers stay valid and the Huffman
// decoder, restarts and IDCT take the damage; seeded valid streams of random
// size, sampling and restart interval decode within the tolerance.
@testable import CoreRaster
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct JPEGFuzzTests {
    typealias F = JPEGFixtures
    static let samplings: [[(h: Int, v: Int)]] = [[(1, 1)], [(1, 1), (1, 1), (1, 1)], [(2, 1), (1, 1), (1, 1)], [(2, 2), (1, 1), (1, 1)]]

    static var seeds: [Data] {
        let grey = F.Frame(width: 19, height: 9, block: F.seeded(0xF1))
        let colour = F.Frame(width: 21, height: 17, sampling: samplings[3], block: F.seeded(0xF2))
        let wide = F.Frame(width: 24, height: 8, sampling: samplings[2], block: F.seeded(0xF3))
        return [F.baseline(grey, restart: 2), F.baseline(colour, orientation: 6), F.baseline(wide, restart: 1, orientation: 8, littleEndian: true)]
    }

    @Test func thousandMutationsThrowOrDecode() {
        fuzz(mutations(of: Self.seeds, count: 1_000, seed: 0x1E6)) { _ = try JPEG.read($0) }
        fuzz(mutations(of: Self.seeds, count: 200, seed: 0x1E7)) { _ = try JPEG.info($0) }
    }

    @Test func scanMutations() {
        var rng = SplitMix64(seed: 0x1E8)
        let cases = (0..<1_000).map { (i: Int) -> Data in
            let parts = F.split(Self.seeds[i % 3]), sosLength = 2 + (Int(parts.scan[2]) << 8 | Int(parts.scan[3]))
            let entropy = mutations(of: [Data(parts.scan.dropFirst(sosLength))], count: 1, seed: rng.next()).first ?? Data()
            return F.join(parts.segments, Array(parts.scan.prefix(sosLength)) + [UInt8](entropy))
        }
        fuzz(cases) { _ = try JPEG.read($0) }
    }

    @Test func seededValidStreamsDecode() throws {
        var rng = SplitMix64(seed: 0x1E9)
        for i in 0..<40 {
            let sampling = Self.samplings[i % 4], restart = Int.random(in: 0...3, using: &rng)
            let f = F.Frame(width: .random(in: 1...40, using: &rng), height: .random(in: 1...40, using: &rng), sampling: sampling, block: F.seeded(rng.next()))
            let e = try F.error(F.baseline(f, restart: restart), f)
            #expect(e.mean <= 1 && e.max <= 4, "case \(i): \(f.width)x\(f.height), restart \(restart), mean \(e.mean), max \(e.max)")
        }
    }
}
