// JPEGReadGuardTests.swift: the JPEG reader's refusals each named by their
// message, not only their kind: a segment cut short names its marker in hex
// (0xFFDB), the refuse-before-allocate block bound names itself for baseline
// and progressive stubs, a SOF with height 0 (height from DNL) is
// unsupported, an interleaved scan of over 10 blocks per MCU (B.2.3) is
// damaged, and seeded cuts of the marker segments always throw.
@testable import CoreRaster
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct JPEGReadGuardTests {
    typealias F = JPEGFixtures

    /// The thrown CodecError, or nil when `body` returns or throws something else.
    func error(_ body: () throws -> Any) -> CodecError? {
        do { _ = try body(); return nil } catch let e as CodecError { return e } catch { return nil }
    }

    func damagedText(_ body: () throws -> Any) -> String? {
        if case .damaged(let text) = error(body) { return text }
        return nil
    }

    @Test func markerInHex() {
        #expect(JPEGDecoder.hex(0xDB) == "0xFFDB" && JPEGDecoder.hex(0x01) == "0xFF01")
        #expect(JPEGDecoder.nibbles(17) == "0x11" && JPEGDecoder.nibbles(0x2A) == "0x2A")
    }

    /// A DQT whose length (67) runs past the bytes: the message names 0xFFDB and where it starts.
    @Test func cutDQTNamesMarker() {
        let data = Data([0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x43, 0x00, 1, 2, 3])
        let text = damagedText { try JPEG.info(data) }
        #expect(text?.contains("0xFFDB") == true && text?.contains("at byte 2") == true, "\(text ?? "no damaged")")
    }

    @Test func badTableNamesItInHex() {
        let dht = Data([0xFF, 0xD8] + F.segment(0xC4, [0x25] + [UInt8](repeating: 0, count: 16)))
        #expect(damagedText { try JPEG.info(dht) }?.contains("DHT class/id 0x25") == true)
        let dqt = Data([0xFF, 0xD8] + F.segment(0xDB, [0x24] + [UInt8](repeating: 1, count: 64)))
        #expect(damagedText { try JPEG.info(dqt) }?.contains("DQT precision/id 0x24") == true)
        let lossless = F.stub(F.Frame(width: 8, height: 8, block: F.seeded(0)), sof: 0xC3)
        guard case .unsupported(let text) = error({ try JPEG.info(lossless) }) else { Issue.record("SOF3 not unsupported"); return }
        #expect(text.contains("0xFFC3"))
    }

    /// Without the bound the walk's overrun would also throw damaged, after allocating the coefficient store.
    @Test func blockBoundNamed() {
        let baseline = F.stub(F.Frame(width: JPEG.maxSide, height: 1, block: F.seeded(0)))
        let progressive = F.stub(F.Frame(width: JPEG.maxSide, height: 8, block: F.seeded(0)), sof: 0xC2)
        for (name, data) in [("baseline", baseline), ("SOF2", progressive)] {
            let text = damagedText { try JPEG.read(data) }
            #expect(text?.contains("blocks in too few bytes") == true, "\(name): \(text ?? "no damaged")")
        }
    }

    @Test func heightFromDNL() {
        let data = F.stub(F.Frame(width: 8, height: 0, block: F.seeded(0)))
        guard case .unsupported(let text) = error({ try JPEG.info(data) }) else { Issue.record("height 0 not unsupported"); return }
        #expect(text.contains("DNL"))
    }

    /// 4x4, 4x4 and 1x1 factors in one interleaved scan are 33 blocks per MCU, over B.2.3's 10.
    @Test func mcuOver10Blocks() {
        for (width, height) in [(1, 1), (32, 32)] {
            let f = F.Frame(width: width, height: height, sampling: [(4, 4), (4, 4), (1, 1)], block: F.seeded(0))
            let text = damagedText { try JPEG.read(F.stub(f)) }
            #expect(text?.contains("33 blocks per MCU") == true, "\(width)x\(height): \(text ?? "no damaged")")
        }
    }

    /// Seeded cuts inside the marker segments throw a CodecError, and a segment cut short names a 0xFF.. marker.
    @Test func seededCutsThrow() {
        var rng = SplitMix64(seed: 0x1C4)
        let good = [UInt8](F.baseline(F.Frame(width: 21, height: 17, sampling: [(2, 2), (1, 1), (1, 1)], block: F.seeded(0x1C5))))
        let headerEnd = good.count - F.split(Data(good)).scan.count
        for _ in 0..<500 {
            let cut = Data(good.prefix(Int.random(in: 3..<headerEnd, using: &rng)))
            let e = error { try JPEG.read(cut) }
            #expect(e != nil, "cut at \(cut.count)")
            if case .damaged(let text) = e, text.contains("past the end") { #expect(text.contains("segment 0xFF"), "\(text)") }
        }
    }
}
