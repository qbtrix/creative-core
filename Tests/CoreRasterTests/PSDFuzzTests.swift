// 1,000 seeded byte mutations of three builder files throw a CodecError or open, each under a second (LC-4).
import CoreRaster
import Foundation
import Testing

func mutations(of seeds: [Data], count: Int, seed: UInt64) -> [Data] {
    var rng = SplitMix64(seed: seed)
    return (0..<count).map { i in
        var b = [UInt8](seeds[i % seeds.count])
        for _ in 0..<Int.random(in: 1...4, using: &rng) where !b.isEmpty {
            let at = Int.random(in: 0..<b.count, using: &rng), v = UInt8.random(in: 0...255, using: &rng)
            if v < 8 { b.removeSubrange(at...) } else if v < 16 { b.insert(v, at: at) } else { b[at] = v < 64 ? [0, 0x7F, 0x80, 0xFF][Int(v) % 4] : v }
        }
        return Data(b)
    }
}

/// Opens every case: an error other than CodecError, or a case over a second, is an issue.
func fuzz(_ cases: [Data], _ open: (Data) throws -> Void) {
    for (i, data) in cases.enumerated() {
        let time = ContinuousClock().measure { do { try open(data) } catch is CodecError {} catch { Issue.record("case \(i): \(error)") } }
        #expect(time < .seconds(1), "case \(i)")
    }
}

@Suite struct PSDFuzzTests {
    @Test(.disabled("waits on LC-4")) func thousandMutationsThrowOrOpen() {
        let seeds = [PSDFile.layers(width: 120, height: 80).data, PSDFile.gray.data, PSDFile.nested.data]
        fuzz(mutations(of: seeds, count: 1_000, seed: 0x95D)) { _ = try PSD.read($0) }
    }
}
