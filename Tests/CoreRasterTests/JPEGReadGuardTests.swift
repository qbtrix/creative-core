// JPEGReadGuardTests.swift: the JPEG reader's refusals each named by their
// message, not only their kind: a segment cut short names its marker in hex
// (0xFFDB), the refuse-before-allocate block bound names itself for baseline
// and progressive stubs at its edge, a SOF with height 0 (left to a DNL
// marker) is unsupported, an interleaved scan of over 10 blocks per MCU or
// of 0 or over 4 components (B.2.3) is damaged, fill bytes and standalone
// markers between segments are skipped, a SOF of no components and a DHT or
// DQT with one bad nibble are damaged, an EXIF IFD0 past its body reads as 1, a second SOF and a scan cut short are named, an EXIF Orientation
// outside 1...8 or not a SHORT reads as 1, a size refusal names its limit,
// a SOF of width 0, a DHT of over 256 values and a segment length under 2 are
// damaged and named, SOF refusals print the values read, and seeded cuts of
// the marker segments and seeded SOF component fields always throw.
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
        // Each byte breaks one nibble only, so each clause of the guard is needed on its own.
        for t: UInt8 in [0x25, 0x05, 0x20] {
            let dht = Data([0xFF, 0xD8] + F.segment(0xC4, [t] + [UInt8](repeating: 0, count: 16)))
            let text = damagedText { try JPEG.info(dht) }
            #expect(text?.contains("DHT class/id \(JPEGDecoder.nibbles(Int(t)))") == true, "\(text ?? "no damaged")")
        }
        // 45 codes of 15 bits and 255 of 16 fit C.2's code space, so only the 256-value limit refuses them.
        // Built as lists of parts: one long `+` chain times out the macOS type checker.
        let table: [[UInt8]] = [[0x00], [UInt8](repeating: 0, count: 14), [45, 255], [UInt8](repeating: 0, count: 300)]
        let segments: [[UInt8]] = [[0xFF, 0xD8], F.segment(0xC4, Array(table.joined()))]
        let many = Data(Array(segments.joined()))
        let manyText = damagedText { try JPEG.info(many) }
        #expect(manyText?.contains("DHT 0x00 has 300 values (256 at most)") == true, "\(manyText ?? "no damaged")")
        for t: UInt8 in [0x24, 0x04, 0x20] {
            let dqt = Data([0xFF, 0xD8] + F.segment(0xDB, [t] + [UInt8](repeating: 1, count: 64)))
            let text = damagedText { try JPEG.info(dqt) }
            #expect(text?.contains("DQT precision/id \(JPEGDecoder.nibbles(Int(t)))") == true, "\(text ?? "no damaged")")
        }
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
            #expect(text?.contains("(4 after the scan header): truncated") == true, "\(name): \(text ?? "no damaged")")
        }
    }

    /// 1024 x 1024 at 4:4:4 is 49,152 blocks; each DC first block is 1 bit or more, so 1,000 bytes cannot code them.
    @Test func progressiveBlockBoundTight() {
        let f = F.Frame(width: 1024, height: 1024, sampling: [(1, 1), (1, 1), (1, 1)], block: F.seeded(0))
        let head = F.header(f, sof: 0xC2, precision: 8, restart: 0, orientation: nil, littleEndian: false)
        let data = Data(head + F.sos([0, 1, 2], 0, 0, 0, 0) + [UInt8](repeating: 0, count: 1_000) + [0xFF, 0xD9])
        let text = damagedText { try JPEG.read(data) }
        #expect(text?.contains("blocks in too few bytes") == true, "\(text ?? "no damaged")")
    }

    /// The bound at its edge: 64 grey blocks pass with 8 bytes left in SOF2 (1 bit a block) and 16 in baseline
    /// (2 bits a block), and one byte fewer is refused, so the multipliers are exactly 8 and 4.
    @Test func blockBoundAtEdge() {
        let f = F.Frame(width: 64, height: 64, block: F.seeded(0))
        for (sof, se, left) in [(UInt8(0xC2), 0, 8), (UInt8(0xC0), 63, 16)] {
            let head = F.header(f, sof: sof, precision: 8, restart: 0, orientation: nil, littleEndian: false) + F.sos([0], 0, se, 0, 0)
            for (bytes, refused) in [(left, false), (left - 1, true)] {
                let data = Data(head + [UInt8](repeating: 0, count: bytes - 2) + [0xFF, 0xD9])
                let text = error { try JPEG.read(data) }.map { "\($0)" } ?? "returned"
                #expect(text.contains("64 blocks in too few bytes") == refused, "SOF \(sof) \(bytes) left: \(text)")
            }
        }
    }

    /// B.2.3: a scan names 1...4 components, so an SOS of 0 (which would decode nothing) or 5 is damaged.
    @Test func scanComponentCount() {
        let grey = F.header(F.Frame(width: 8, height: 8, block: F.seeded(0)), sof: 0xC0, precision: 8, restart: 0,
                            orientation: nil, littleEndian: false)
        let three = F.Frame(width: 8, height: 8, sampling: [(1, 1), (1, 1), (1, 1)], block: F.seeded(0))
        let colour = F.header(three, sof: 0xC0, precision: 8, restart: 0, orientation: nil, littleEndian: false)
        let five: [UInt8] = [5, 1, 0x00, 2, 0x11, 3, 0x11, 1, 0x00, 2, 0x11, 0, 63, 0]
        for (count, data) in [(0, grey + F.segment(0xDA, [0, 0, 63, 0])), (5, colour + F.segment(0xDA, five))] {
            let text = damagedText { try JPEG.read(Data(data + [UInt8](repeating: 0, count: 8) + [0xFF, 0xD9])) }
            #expect(text?.contains("scan names \(count) components") == true, "\(text ?? "no damaged")")
        }
    }

    /// B.1.1.2: 0xFF fill bytes before a marker, TEM and an RSTm between segments are skipped, so the pixels match.
    @Test func fillBytesAndStandaloneMarkers() throws {
        let good = F.baseline(F.Frame(width: 13, height: 7, sampling: [(2, 1), (1, 1), (1, 1)], block: F.seeded(0x11)))
        let parts = F.split(good)
        let fill: [UInt8] = [0xFF, 0xFF, 0xFF, 0x01, 0xFF, 0xD3, 0xFF]
        let padded: [UInt8] = parts.segments.flatMap { fill + F.segment($0.marker, $0.body) }
        let soi: [UInt8] = [0xFF, 0xD8]
        #expect(try JPEG.read(Data(soi + padded + parts.scan)) == JPEG.read(good))
    }

    /// A SOF of no components is damaged (not unsupported); an EXIF IFD0 offset past the TIFF body reads as 1.
    @Test func noComponentsAndFarIFD() throws {
        let sof = F.segment(0xC0, [8] + F.be16(8) + F.be16(8) + [0])
        #expect(damagedText { try JPEG.info(Data([0xFF, 0xD8] + sof + [0xFF, 0xD9])) }?.contains("no components") == true)
        let parts = F.split(F.baseline(F.Frame(width: 8, height: 8, block: F.seeded(0x12))))
        let tiff: [UInt8] = Array("Exif".utf8) + [0, 0] + Array("MM".utf8) + [0, 42, 0x00, 0x00, 0xFF, 0xFF]
        #expect(try JPEG.info(F.join([(0xE1, tiff)] + parts.segments, parts.scan)).orientation == 1)
    }

    /// An 8 x 8 baseline scan, then a SOF for 64 x 64: the store was sized for the first frame, so the second is refused.
    @Test func secondSOF() {
        let first = [UInt8](F.baseline(F.Frame(width: 8, height: 8, block: F.seeded(0x2F))).dropLast(2))
        let sof = F.segment(0xC0, [8] + F.be16(64) + F.be16(64) + [1, 1, 0x11, 0])
        let data = Data(first + sof + F.sos([0], 0, 63, 0, 0) + [0x12, 0x34, 0xFF, 0xD9])
        let text = damagedText { try JPEG.read(data) }
        #expect(text?.contains("a second SOF") == true, "\(text ?? "no damaged")")
    }

    /// DC and AC tables of two 1-bit codes, both value 0, decode a whole block from padding 1-bits alone, so only the
    /// overrun check refuses a scan with no entropy bytes.
    @Test func shortScanNamed() {
        let f = F.Frame(width: 8, height: 8, block: F.seeded(0))
        let two = F.Huffman(bits: [2] + [Int](repeating: 0, count: 15), values: [0, 0])
        // Built as lists of parts: one long `+` chain times out the macOS type checker.
        let frame: [[UInt8]] = [[8], F.be16(8), F.be16(8), [1, 1, 0x11, 0]]
        let sof = F.segment(0xC0, Array(frame.joined()))
        let parts: [[UInt8]] = [[0xFF, 0xD8], F.dqt(0, f.tables[0]), sof, F.dht(0, 0, two), F.dht(1, 0, two),
                                F.sos([0], 0, 63, 0, 0), [0xFF, 0xD9]]
        let data = Data(Array(parts.joined()))
        let text = damagedText { try JPEG.read(data) }
        #expect(text?.contains("scan ends at MCU 0") == true, "\(text ?? "no damaged")")
    }

    /// JPEGInfo.orientation is 1...8: an EXIF Orientation of 0 or 9 is no usable tag, so 1.
    @Test func exifOrientationOutOfRange() throws {
        let f = F.Frame(width: 13, height: 7, sampling: [(1, 1), (1, 1), (1, 1)], block: F.seeded(0x0E))
        for value in [0, 9] {
            #expect(try JPEG.info(F.baseline(f, orientation: value, littleEndian: false)).orientation == 1, "\(value)")
        }
    }

    /// An Orientation entry of type ASCII (2) or LONG (4), even one whose first two value bytes read 6
    /// (little-endian), is no SHORT Orientation tag, so 1.
    @Test func exifOrientationWrongType() throws {
        let parts = F.split(F.baseline(F.Frame(width: 13, height: 7, block: F.seeded(0x0F))))
        for type in [2, 4] {
            let app1 = Array(F.exif(6, littleEndian: true, type: type).dropFirst(4))
            #expect(try JPEG.info(F.join([(0xE1, app1)] + parts.segments, parts.scan)).orientation == 1, "type \(type)")
        }
        let short = Array(F.exif(6, littleEndian: true).dropFirst(4))
        #expect(try JPEG.info(F.join([(0xE1, short)] + parts.segments, parts.scan)).orientation == 6)
    }

    /// JPEGInfo's width is 1...maxSide: a SOF of width 0 is damaged, from info and from read.
    @Test func widthZero() {
        let data = F.stub(F.Frame(width: 0, height: 8, block: F.seeded(0)))
        let info = damagedText { try JPEG.info(data) }, read = damagedText { try JPEG.read(data) }
        #expect(info?.contains("width 0") == true, "info: \(info ?? "no damaged")")
        #expect(read?.contains("width 0") == true, "read: \(read ?? "no damaged")")
    }

    /// A segment length counts its own two bytes, so 1 is damaged and named, not a body that ends before it starts.
    @Test func segmentLengthUnderTwo() {
        let text = damagedText { try JPEG.info(Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9])) }
        #expect(text?.contains("segment 0xFFE0 at byte 2") == true && text?.contains("length 1") == true, "\(text ?? "no damaged")")
    }

    /// SOF refusals print what was read: the H and V of a 0x55 sampling byte, a Tq of 5, and CMYK for 4 components.
    @Test func sofRefusalsPrintValues() {
        let parts = F.split(F.stub(F.Frame(width: 8, height: 8, block: F.seeded(0))))
        func sof(_ hv: UInt8, _ tq: UInt8) -> Data {
            var segments = parts.segments
            if let i = segments.firstIndex(where: { $0.marker == 0xC0 }) { (segments[i].body[7], segments[i].body[8]) = (hv, tq) }
            return F.join(segments, parts.scan)
        }
        // 0x51, 0x01 and 0x15 break H or V alone, so each clause of the sampling guard is needed on its own.
        let cases: [(UInt8, UInt8, String)] = [(0x55, 0, "SOF component 1: H 5 V 5 Tq 0"), (0x11, 5, "SOF component 1: H 1 V 1 Tq 5"),
                                               (0x51, 0, "SOF component 1: H 5 V 1"), (0x01, 0, "SOF component 1: H 0 V 1"),
                                               (0x15, 0, "SOF component 1: H 1 V 5")]
        for (hv, tq, want) in cases {
            let text = damagedText { try JPEG.info(sof(hv, tq)) }
            #expect(text?.contains(want) == true, "\(text ?? "no damaged")")
        }
        let cmyk = F.baseline(F.Frame(width: 8, height: 8, sampling: [(1, 1), (1, 1), (1, 1), (1, 1)], block: F.seeded(0x06)))
        guard case .unsupported(let text) = error({ try JPEG.info(cmyk) }) else { Issue.record("4 components not unsupported"); return }
        #expect(text.contains("4 components") && text.contains("CMYK"), "\(text)")
    }

    /// Seeded component count, sampling and Tq bytes in a SOF throw a CodecError or decode, never trap.
    @Test func seededSOFFieldsThrow() {
        var rng = SplitMix64(seed: 0x50F)
        let good = F.split(F.baseline(F.Frame(width: 16, height: 8, sampling: [(2, 1), (1, 1), (1, 1)], block: F.seeded(0x510))))
        guard let at = good.segments.firstIndex(where: { $0.marker == 0xC0 }) else { Issue.record("no SOF"); return }
        for _ in 0..<400 {
            var segments = good.segments
            for k in [5, 7, 8, 10, 11, 13, 14] where Int.random(in: 0..<3, using: &rng) == 0 {
                segments[at].body[k] = UInt8.random(in: 0...255, using: &rng)
            }
            let data = F.join(segments, good.scan)
            do { _ = try JPEG.read(data) } catch is CodecError {} catch { Issue.record("\(error)") }
        }
    }

    /// Each size refusal names the limit it hit: a side over `maxSide`, or a pixel count over `PixelBuffer.maxPixels`.
    @Test func tooLargeNamesLimit() {
        for (width, height, limit) in [(JPEG.maxSide + 1, 1, JPEG.maxSide), (1, JPEG.maxSide + 1, JPEG.maxSide),
                                       (20_000, 20_000, PixelBuffer.maxPixels)] {
            let data = F.stub(F.Frame(width: width, height: height, block: F.seeded(0)))
            guard case .tooLarge(let text) = error({ try JPEG.read(data) }) else { Issue.record("\(width)x\(height) not tooLarge"); continue }
            #expect(text.hasPrefix("JPEG \(width)x\(height)") && text.contains("\(limit)"), "\(text)")
        }
    }

    @Test func heightFromDNL() {
        let data = F.stub(F.Frame(width: 8, height: 0, block: F.seeded(0)))
        guard case .unsupported(let text) = error({ try JPEG.info(data) }) else { Issue.record("height 0 not unsupported"); return }
        #expect(text.contains("height 0") && text.contains("DNL"), "\(text)")
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
