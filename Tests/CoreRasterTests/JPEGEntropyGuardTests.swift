// JPEGEntropyGuardTests.swift: the entropy decoder's guards on untrusted
// bytes, each named by its `damaged` message: a DHT with more codes than a
// length holds (C.2), a DC size over 15 in sequential and progressive scans,
// an AC run past coefficient 63 or past a progressive band's end, a
// refinement symbol of size 2 (G.1.2.3), a restart interval the RSTm markers
// do not deliver (B.2.4.4), a scan table no DHT defined; the SOF component id
// (not its array position) in progressive order errors; and seeded random
// DHT tables over random scan bytes throw or decode, never trap.
@testable import CoreRaster
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct JPEGEntropyGuardTests {
    typealias F = JPEGFixtures
    static var grey: F.Frame { F.Frame(width: 8, height: 8, block: F.seeded(0xE1)) }
    static let zeros = [UInt8](repeating: 0, count: 8)

    func damagedText(_ bytes: [UInt8]) -> String? {
        do { _ = try JPEG.read(Data(bytes + [0xFF, 0xD9])); return nil } catch CodecError.damaged(let text) { return text } catch { return nil }
    }

    static func head(_ f: F.Frame = grey, sof: UInt8, restart: Int = 0) -> [UInt8] {
        F.header(f, sof: sof, precision: 8, restart: restart, orientation: nil, littleEndian: false)
    }

    /// Entropy bytes: `put` writes symbols of `codes` and raw bits, then 1-bits pad the byte.
    static func coded(_ body: (inout F.Bits) -> Void) -> [UInt8] {
        var w = F.Bits()
        body(&w); w.align()
        return w.bytes + zeros
    }

    @Test func entropyGuardsNamed() {
        let dc16 = F.dht(0, 0, F.Huffman(bits: [1] + [Int](repeating: 0, count: 15), values: [16]))
        let dc = F.huffman[0].dc, ac = F.huffman[0].ac
        let progressive = Self.head(sof: 0xC2) + F.sos([0], 0, 0, 0, 0) + Self.zeros
        let two = F.Frame(width: 16, height: 8, block: F.seeded(0xE2))
        let cases: [(String, [UInt8], String)] = [
            ("3 one-bit codes", [0xFF, 0xD8] + F.segment(0xC4, [0x00, 3] + [UInt8](repeating: 0, count: 15) + [0, 1, 2]),
             "too many 1-bit codes"),
            ("baseline DC value 16", Self.head(sof: 0xC0) + dc16 + F.sos([0], 0, 63, 0, 0) + Self.zeros, "DC size 16"),
            ("progressive DC value 16", Self.head(sof: 0xC2) + dc16 + F.sos([0], 0, 0, 0, 0) + Self.zeros, "DC size 16"),
            ("three ZRL then 0xF1", Self.head(sof: 0xC0) + F.sos([0], 0, 63, 0, 0) + Self.coded { w in
                w.put(dc, 0); for _ in 0..<3 { w.put(ac, 0xF0) }; w.put(ac, 0xF1); w.put(1, 1)
            }, "past coefficient 63"),
            ("DRI 1 over 2 MCUs, no RST0", Self.head(two, sof: 0xC0, restart: 1) + F.sos([0], 0, 63, 0, 0) + Self.coded { w in
                for _ in 0..<2 { w.put(dc, 0); w.put(ac, 0x00) }
            }, "restart interval 1 missing"),
            ("refinement symbol of size 2", progressive + F.sos([0], 1, 63, 0, 1) + [0xAF] + F.sos([0], 1, 63, 1, 0)
             + Self.coded { $0.put(ac, 0x02); $0.put(3, 2) }, "refinement size 2"),
            ("band 1...5, run 5", progressive + F.sos([0], 1, 5, 0, 0) + Self.coded { $0.put(ac, 0x51); $0.put(1, 1) },
             "past coefficient 5"),
            ("table 2 never defined", Self.head(sof: 0xC0) + F.segment(0xDA, [1, 1, 0x22, 0, 63, 0]) + Self.zeros, "no DHT DC table"),
        ]
        for (name, bytes, message) in cases {
            let text = damagedText(bytes)
            #expect(text?.contains(message) == true, "\(name): \(text ?? "no damaged")")
        }
        // The walk names the SOF component id (1 here) and the unit of a block's error.
        #expect(damagedText(cases[1].1)?.contains("component 1 unit 0") == true)
    }

    /// An AC scan before its DC scan names SOF component id 1, which a marker dump shows, not array index 0.
    @Test func progressiveOrderNamesComponentID() {
        let text = damagedText(Self.head(sof: 0xC2) + F.sos([0], 1, 63, 0, 0) + Self.zeros)
        #expect(text?.contains("component 1 coefficients") == true, "\(text ?? "no damaged")")
    }

    /// Seeded random DHT tables (DC and AC, ids 0 and 1, no 1-bit codes and 0...2 per longer length) over random scan bytes, in
    /// sequential and progressive frames, throw a CodecError or decode, never trap or hang.
    @Test func seededTablesThrowOrDecode() {
        var rng = SplitMix64(seed: 0xE3)
        let cases = (0..<400).map { (i: Int) -> Data in
            let tables = (0..<4).flatMap { (t: Int) -> [UInt8] in
                let counts = (0..<16).map { $0 == 0 ? 0 : UInt8.random(in: 0...2, using: &rng) }
                let values = counts.flatMap { (0..<Int($0)).map { _ in UInt8.random(in: 0...255, using: &rng) } }
                return F.segment(0xC4, [UInt8((t >> 1) << 4 | t & 1)] + counts + values)
            }
            let scan = i % 2 == 0 ? F.sos([0], 0, 63, 0, 0) : F.sos([0], 0, 0, 0, Int.random(in: 0...2, using: &rng))
            let entropy = (0..<16).map { _ in UInt8.random(in: 0...0xFE, using: &rng) }
            return Data(Self.head(sof: i % 2 == 0 ? 0xC0 : 0xC2, restart: i % 3) + tables + scan + entropy + [0xFF, 0xD9])
        }
        fuzz(cases) { _ = try JPEG.read($0) }
    }
}
