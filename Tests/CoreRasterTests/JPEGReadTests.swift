// JPEGReadTests.swift: JPEG.info and JPEG.read against JPEGs built from
// ITU-T T.81, JFIF 1.02 and EXIF 2.3 (JPEGFixtures), each within a mean of
// 1/255 and a maximum of 4/255 of its A.3.3 reference: grey and YCbCr at
// 4:4:4, 4:2:2 and 4:2:0, the zigzag order, restart intervals, the EXIF
// orientation reported but not applied (and its documented PixelBuffer calls
// turning each of 1...8 upright), and unsupported, oversized or
// damaged files refused; progressive codings (Annex G, with EOB runs and
// restart intervals) read as their baseline ones do, and progressive scans out
// of Annex G's order or limits, or past the scan work budget, refused.
@testable import CoreRaster
import CoreColor
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct JPEGReadTests {
    typealias F = JPEGFixtures
    static let samplings: [[(h: Int, v: Int)]] = [[(1, 1), (1, 1), (1, 1)], [(2, 1), (1, 1), (1, 1)], [(2, 2), (1, 1), (1, 1)]]

    func check(_ f: F.Frame, _ data: Data, _ note: String) throws {
        let e = try F.error(data, f)
        #expect(e.mean <= 1 && e.max <= 4, "\(note): mean \(e.mean), max \(e.max) levels")
    }

    @Test func infoReadsFrame() throws {
        let colour = F.Frame(width: 37, height: 21, sampling: Self.samplings[2], block: F.seeded(0x1F))
        #expect(try JPEG.info(F.baseline(colour)) == JPEGInfo(width: 37, height: 21, components: 3, progressive: false, orientation: 1))
        #expect(try JPEG.info(F.stub(colour, sof: 0xC2)).progressive)
        let tall = F.Frame(width: 1, height: JPEG.maxSide, block: F.seeded(0))
        #expect(try JPEG.info(F.stub(tall)) == JPEGInfo(width: 1, height: JPEG.maxSide, components: 1, progressive: false, orientation: 1))
    }

    /// DC only, the inverse DCT is flat: S00 = 16q (K.1) gives samples 128 + 2q (A.3.3, C(0)² = 1/2).
    @Test func greyDCOnly() throws {
        let dc = [-64, -20, 0, 1, 37, 63]
        let f = F.Frame(width: 48, height: 8, block: { _, x, _ in [dc[x]] + [Int](repeating: 0, count: 63) })
        let read = try JPEG.read(F.baseline(f))
        for y in [0, 7] {
            for x in 0..<48 {
                let p = try read.pixel(x: x, y: y)
                #expect(abs(TransferCurve.encode(Double(p.r)) * 255 - Double(128 + 2 * dc[x / 8])) <= 0.01, "x \(x)")
                #expect(p.r == p.g && p.g == p.b && p.a == 1)
            }
        }
    }

    /// 64 blocks under a flat table of 16, block k holding DC k - 32 and only zigzag coefficient k (Figure A.6) at ±4:
    /// a swapped zigzag entry moves a coefficient to another frequency, about 11 levels off.
    @Test func zigzag() throws {
        let flat = [Int](repeating: 16, count: 64)
        let f = F.Frame(width: 64, height: 64, tables: [flat, flat], block: { _, x, y in
            var q = [Int](repeating: 0, count: 64), k = y * 8 + x
            q[0] = k - 32
            if k > 0 { q[F.zigzag[k]] = k % 2 == 0 ? 4 : -4 }
            return q
        })
        try check(f, F.baseline(f), "one coefficient per block")
    }

    @Test func ycbcrSampling() throws {
        for sampling in Self.samplings {
            for (width, height) in [(13, 11), (37, 21)] {
                let f = F.Frame(width: width, height: height, sampling: sampling, block: F.seeded(UInt64(width * 10 + sampling[0].h * 2 + sampling[0].v)))
                try check(f, F.baseline(f), "\(sampling[0].h)x\(sampling[0].v) at \(width)x\(height)")
            }
        }
        let grey = F.Frame(width: 21, height: 9, block: F.seeded(0x6E))
        try check(grey, F.baseline(grey), "grey")
        let colour = F.Frame(width: 19, height: 17, sampling: Self.samplings[2], block: F.seeded(0x6F))
        #expect(try JPEG.read(F.baseline(colour, sof: 0xC1)) == JPEG.read(F.baseline(colour)), "SOF1 at 8 bits reads as SOF0")
    }

    /// DRI (B.2.4.4): RSTm after every n MCUs, m wrapping after 7; each resets the DC predictions to 0 (F.2.1.3.1).
    /// 80 x 16 grey is 20 one-block MCUs, so interval 1 wraps m twice.
    @Test func restartResetsDC() throws {
        let grey = F.Frame(width: 80, height: 16, block: F.seeded(0x71))
        for n in [1, 3] { try check(grey, F.baseline(grey, restart: n), "grey every \(n)") }
        let colour = F.Frame(width: 48, height: 40, sampling: Self.samplings[2], block: F.seeded(0x72))
        for n in [1, 2, 4] { try check(colour, F.baseline(colour, restart: n), "4:2:0 every \(n)") }
        #expect(try JPEG.read(F.baseline(colour, restart: 2)) == JPEG.read(F.baseline(colour)))
    }

    @Test func exifOrientation() throws {
        let f = F.Frame(width: 13, height: 7, sampling: Self.samplings[1], block: F.seeded(0x0E))
        let plain = try JPEG.read(F.baseline(f))
        for (orientation, little) in [(6, false), (8, true), (3, false), (1, true)] {
            let data = F.baseline(f, orientation: orientation, littleEndian: little)
            #expect(try JPEG.info(data) == JPEGInfo(width: 13, height: 7, components: 3, progressive: false, orientation: orientation))
            #expect(try JPEG.read(data) == plain, "pixels are not rotated")
        }
    }

    /// Each EXIF orientation's documented `JPEGInfo.orientation` calls turn a 2 x 3 frame upright: the result matches
    /// the EXIF 2.3 definition (where the stored 0th row and 0th column are shown) applied to the stored pixels.
    @Test func orientationCallsTurnUpright() throws {
        let f = F.Frame(width: 2, height: 3, sampling: Self.samplings[0], block: F.seeded(0x0D))
        let stored = try JPEG.read(F.baseline(f)), w = stored.width, h = stored.height
        func upright(_ b: PixelBuffer, _ o: Int) -> PixelBuffer {
            switch o {
            case 2: b.flipped(.horizontal)
            case 3: b.rotated(.degrees180)
            case 4: b.flipped(.vertical)
            case 5: b.rotated(.degrees90).flipped(.horizontal)
            case 6: b.rotated(.degrees90)
            case 7: b.rotated(.degrees270).flipped(.horizontal)
            case 8: b.rotated(.degrees270)
            default: b
            }
        }
        // EXIF 2.3 Orientation: the stored pixel shown at display (x, y).
        let source: [Int: (Int, Int) -> (Int, Int)] = [
            1: { ($0, $1) }, 2: { (w - 1 - $0, $1) }, 3: { (w - 1 - $0, h - 1 - $1) }, 4: { ($0, h - 1 - $1) },
            5: { ($1, $0) }, 6: { ($1, h - 1 - $0) }, 7: { (w - 1 - $1, h - 1 - $0) }, 8: { (w - 1 - $1, $0) },
        ]
        for o in 1...8 {
            let data = F.baseline(f, orientation: o, littleEndian: o % 2 == 0)
            #expect(try JPEG.info(data).orientation == o)
            let shown = upright(try JPEG.read(data), o)
            #expect(shown.width == (o >= 5 ? h : w) && shown.height == (o >= 5 ? w : h), "\(o)")
            for y in 0..<shown.height {
                for x in 0..<shown.width {
                    let (sx, sy) = source[o].map { $0(x, y) } ?? (x, y)
                    #expect(try shown.pixel(x: x, y: y) == stored.pixel(x: sx, y: sy), "orientation \(o) at (\(x), \(y))")
                }
            }
        }
    }

    /// Arithmetic coding (SOF9, SOF10), lossless (SOF3) and hierarchical (SOF5) frames, 12-bit samples and four components.
    @Test func unsupportedThrows() throws {
        let grey = F.Frame(width: 8, height: 8, block: F.seeded(0x05))
        for marker: UInt8 in [0xC9, 0xCA, 0xC3, 0xC5] {
            let data = F.baseline(grey, sof: marker)
            #expect(PNGFixtures.thrown { try JPEG.info(data) } == "unsupported", "SOF \(marker)")
            #expect(PNGFixtures.thrown { try JPEG.read(data) } == "unsupported", "SOF \(marker)")
        }
        #expect(PNGFixtures.thrown { try JPEG.read(F.baseline(grey, sof: 0xC1, precision: 12)) } == "unsupported")
        let cmyk = F.Frame(width: 8, height: 8, sampling: [(1, 1), (1, 1), (1, 1), (1, 1)], block: F.seeded(0x06))
        #expect(PNGFixtures.thrown { try JPEG.read(F.baseline(cmyk)) } == "unsupported")
    }

    /// Sizes come from SOF and are refused before any pixel buffer: the scans here are two bytes, so `tooLarge`
    /// (not `damaged`) shows the check came first. 20,000² is within the side limit and over `PixelBuffer.maxPixels`.
    @Test func refusesHuge() throws {
        for (width, height) in [(JPEG.maxSide + 1, 1), (1, JPEG.maxSide + 1), (20_000, 20_000)] {
            for sampling in [[(1, 1)], Self.samplings[2]] {
                let data = F.stub(F.Frame(width: width, height: height, sampling: sampling, block: F.seeded(0)))
                #expect(PNGFixtures.thrown { try JPEG.read(data) } == "tooLarge", "\(width)x\(height)")
                let overSide = width > JPEG.maxSide || height > JPEG.maxSide
                #expect(PNGFixtures.thrown { try JPEG.info(data) } == (overSide ? "tooLarge" : "returned"))
            }
        }
        #expect(PNGFixtures.thrown { try JPEG.read(F.stub(F.Frame(width: JPEG.maxSide, height: 1, block: F.seeded(0)))) } == "damaged")
        #expect(PNGFixtures.thrown { try JPEG.read(F.stub(F.Frame(width: JPEG.maxSide, height: 8, block: F.seeded(0)), sof: 0xC2)) } == "damaged")
    }

    @Test func damagedThrows() throws {
        let f = F.Frame(width: 16, height: 16, sampling: Self.samplings[2], block: F.seeded(0xDA))
        let good = F.baseline(f), parts = F.split(good)
        let without = { (drop: (UInt8, [UInt8]) -> Bool) -> Data in F.join(parts.segments.filter { !drop($0.marker, $0.body) }, parts.scan) }
        let sosLength = 2 + (Int(parts.scan[2]) << 8 | Int(parts.scan[3]))
        var badSampling = parts.segments, badSelector = parts.scan
        if let i = badSampling.firstIndex(where: { $0.marker == 0xC0 }) { badSampling[i].body[10] = 0x00 }  // component 2: H = V = 0
        badSelector[5] = 9  // the scan names component 9
        let cases: [(String, Data)] = [
            ("no DHT", without { m, _ in m == 0xC4 }), ("no DQT", without { m, _ in m == 0xDB }),
            ("no DQT 1", without { m, b in m == 0xDB && b.first == 1 }), ("no scan", F.join(parts.segments, [0xFF, 0xD9])),
            ("cut in the scan", Data(good.prefix(good.count - parts.scan.count + sosLength + 4))),
            ("no code of 16 ones (C.2)", F.join(parts.segments, Array(parts.scan.prefix(sosLength)) + [UInt8](repeating: 0xFF, count: 8).flatMap { [$0, 0] } + [0xFF, 0xD9])),
            ("sampling 0", F.join(badSampling, parts.scan)), ("unknown component", F.join(parts.segments, badSelector)),
        ]
        for (name, data) in cases { #expect(PNGFixtures.thrown { try JPEG.read(data) } == "damaged", "\(name)") }
        // The SOS refuses a component whose DQT is missing before the scan is decoded, naming the component.
        do { _ = try JPEG.read(without { m, b in m == 0xDB && b.first == 1 }) } catch CodecError.damaged(let text) {
            #expect(text == "scan component 2 uses DQT 1, not defined before its scan", "\(text)")
        } catch { Issue.record("no DQT 1: \(error)") }
        for data in [without { m, _ in m == 0xC0 }, Data([0xFF, 0xD8, 0xFF, 0xE0, 0xFF, 0xF0, 0x4A, 0x46])] {
            #expect(PNGFixtures.thrown { try JPEG.info(data) } == "damaged", "no SOF, or a segment past the end")
            #expect(PNGFixtures.thrown { try JPEG.read(data) } == "damaged")
        }
        #expect(PNGFixtures.thrown { try JPEG.info(Data(good.dropFirst())) } == "notThisFormat")
        #expect(PNGFixtures.thrown { try JPEG.read(Data(PNGFixtures.signature)) } == "notThisFormat")
    }

    /// `f` coded progressive (JPEGFixtures.progressive) reads as its baseline coding does, within 1/255 per channel.
    func sameAsBaseline(_ f: F.Frame, _ note: String, restart: Int = 0) throws {
        let data = F.progressive(f, restart: restart), a = try JPEG.read(data), b = try JPEG.read(F.baseline(f))
        #expect(try JPEG.info(data).progressive)
        #expect(a.width == f.width && a.height == f.height, "\(note)")
        var worst = 0.0
        for i in 0..<(min(a.width, b.width) * min(a.height, b.height)) {
            let p = try a.pixel(x: i % a.width, y: i / a.width), q = try b.pixel(x: i % a.width, y: i / a.width)
            for (u, v) in [(p.r, q.r), (p.g, q.g), (p.b, q.b)] { worst = max(worst, abs(TransferCurve.encode(Double(u)) - TransferCurve.encode(Double(v))) * 255) }
        }
        #expect(worst <= 1, "\(note): \(worst) levels from the baseline decode")
        try check(f, data, note)
    }

    @Test func progressiveMatchesBaseline() throws {
        try sameAsBaseline(F.Frame(width: 21, height: 9, block: F.seeded(0x91)), "grey")
        for (i, sampling) in Self.samplings.enumerated() {
            try sameAsBaseline(F.Frame(width: 37, height: 21, sampling: sampling, block: F.seeded(0x92 + UInt64(i))), "\(sampling[0].h)x\(sampling[0].v)")
        }
    }

    /// Luma AC at Al 1 then refined (G.1.2.3): the refinement carries every low bit and every ±1, so skipping it is
    /// levels off. Zigzag 2...17 are 16 zero-history zeros before a refined coefficient, which takes a ZRL first.
    @Test func acRefinement() throws {
        let flat = [Int](repeating: 16, count: 64)
        let f = F.Frame(width: 16, height: 16, tables: [flat, flat], block: { _, x, y in
            var q = [Int](repeating: 0, count: 64)
            for (k, v) in [(1, 5), (18, -3), (20, 1), (40, -1), (45, 2), (63, 3)] { q[F.zigzag[k]] = x == y ? v : -v }
            return q
        })
        try sameAsBaseline(f, "refined")
    }

    /// G.1.2.2 and G.1.2.3 end-of-band runs: 64 x 64 grey with AC only in every 5th block (blocks 16...58 none), so
    /// first and refinement scans code EOB2 (+1) runs, with correction bits, and one EOB5 (+13) over the gap.
    @Test func progressiveEOBRuns() throws {
        let f = F.Frame(width: 64, height: 64, block: { _, x, y in
            var q = [Int](repeating: 0, count: 64), k = y * 8 + x
            q[0] = k - 32
            guard k % 5 == 0, !(16...58).contains(k) else { return q }
            for (z, v) in [(1, 5), (2, 1), (4, -3), (9, -1), (12, 2)] { q[F.zigzag[z]] = k % 2 == 0 ? v : -v }
            return q
        })
        try sameAsBaseline(f, "EOB runs")
    }

    /// B.2.4.4 in a progressive frame: RSTm every n units of each scan ends the EOB run and resets the DC predictions.
    @Test func progressiveRestart() throws {
        for n in [1, 3] {
            try sameAsBaseline(F.Frame(width: 80, height: 16, block: F.seeded(0x96)), "grey every \(n)", restart: n)
            try sameAsBaseline(F.Frame(width: 48, height: 40, sampling: Self.samplings[2], block: F.seeded(0x97)), "4:2:0 every \(n)", restart: n)
        }
        // Two blocks, an interval each: block 0's EOB1 claims more blocks than its interval holds, yet the restart
        // ends the run, so interval 1's DC (from prediction 0) and its coefficient 3 are read.
        let f = F.Frame(width: 16, height: 8, block: { _, x, _ in (x == 0 ? [7, 0] : [-5, 3]) + [Int](repeating: 0, count: 62) })
        func coded(_ a: (inout F.Bits) -> Void, _ b: (inout F.Bits) -> Void) -> [UInt8] {
            var w = F.Bits()
            a(&w); w.align(); w.bytes += [0xFF, 0xD0]; b(&w); w.align()
            return w.bytes
        }
        let dc = F.huffman[0].dc, ac = F.codes(F.acAll)
        let dcScan = coded({ $0.put(dc, 3); $0.put(7, 3) }, { $0.put(dc, 3); $0.put(2, 3) })
        let acScan = coded({ $0.put(ac, 0x10); $0.put(0, 1) }, { $0.put(ac, 0x02); $0.put(3, 2); $0.put(ac, 0x00) })
        let head = F.header(f, sof: 0xC2, precision: 8, restart: 1, orientation: nil, littleEndian: false, ac: (F.acAll, F.acAll))
        // Built as a list of parts: one long `+` chain times out the macOS type checker.
        let parts: [[UInt8]] = [head, F.sos([0], 0, 0, 0, 0), dcScan, F.sos([0], 1, 63, 0, 0), acScan, [0xFF, 0xD9]]
        let data = Data(Array(parts.joined()))
        #expect(try JPEG.read(data) == JPEG.read(F.baseline(f)))
    }

    /// `JPEGDecoder.passes`: an 8 x 8 grey SOF2 is one block, so a DC scan and 63 single-coefficient AC first scans
    /// (one EOB each) are 64 visits and decode; one refinement scan more is `tooLarge`.
    @Test func progressiveScanBudget() throws {
        let f = F.Frame(width: 8, height: 8, block: F.seeded(0x98))
        let head = F.header(f, sof: 0xC2, precision: 8, restart: 0, orientation: nil, littleEndian: false)
        let firsts = (1...63).flatMap { (k: Int) -> [UInt8] in F.sos([0], k, k, 0, 1) + [0xAF] }
        let scans = head + F.sos([0], 0, 0, 0, 0) + [UInt8](repeating: 0, count: 8) + firsts
        #expect(PNGFixtures.thrown { try JPEG.read(Data(scans + [0xFF, 0xD9])) } == "returned")
        let over = Data(scans + F.sos([0], 1, 1, 1, 0) + [0xAF, 0xFF, 0xD9])
        #expect(PNGFixtures.thrown { try JPEG.read(over) } == "tooLarge")
        do { _ = try JPEG.read(over) } catch CodecError.tooLarge(let text) {
            #expect(text.contains("progressive scans"), "\(text)")
        } catch { Issue.record("\(error)") }
    }

    /// B.2.3 and G.1.1.1 on an 8 x 8 grey SOF2: DC first, its refinement and an AC band (one EOB) decode; each bad scan
    /// after the DC first scan (or first, for AC before DC) is damaged.
    @Test func progressiveScanChecks() throws {
        let f = F.Frame(width: 8, height: 8, block: F.seeded(0x93)), zeros = [UInt8](repeating: 0, count: 8)
        let head = F.header(f, sof: 0xC2, precision: 8, restart: 0, orientation: nil, littleEndian: false)
        let dc = F.sos([0], 0, 0, 0, 1) + zeros
        func read(_ scans: [UInt8]...) -> String { PNGFixtures.thrown { try JPEG.read(Data(head + scans.joined() + [0xFF, 0xD9])) } }
        #expect(read(dc, F.sos([0], 0, 0, 1, 0) + zeros, F.sos([0], 1, 63, 0, 0) + [0xAF]) == "returned")
        let bad: [(String, [UInt8])] = [
            ("DC band 0...5", F.sos([0], 0, 5, 0, 0)), ("band 5...3", F.sos([0], 5, 3, 0, 0)), ("band past 63", F.sos([0], 1, 64, 0, 0)),
            ("Al 14", F.sos([0], 0, 0, 0, 14)), ("Ah 2 after Al 1", F.sos([0], 0, 0, 2, 1)), ("DC coded twice", F.sos([0], 0, 0, 0, 1)),
            ("refinement of an uncoded band", F.sos([0], 1, 63, 1, 0)),
        ]
        for (name, scan) in bad { #expect(read(dc, scan + zeros) == "damaged", "\(name)") }
        let pastBand: [[UInt8]] = [head, dc, F.sos([0], 1, 64, 0, 0), zeros, [0xFF, 0xD9]]
        do { _ = try JPEG.read(Data(Array(pastBand.joined()))) } catch CodecError.damaged(let text) {
            #expect(text.contains("scan band 1...64: a band must run up within 0...63"), "\(text)")
        } catch { Issue.record("band past 63: \(error)") }
        // Each a first scan with nothing coded before it, or a refinement whose Ah matches what was coded, so only
        // its own G.1.1.1 clause refuses it: Al over 13, a DC band past 0, and Ah 2 with Al 0 (not Ah - 1).
        #expect(read(F.sos([0], 0, 0, 0, 14) + zeros) == "damaged", "Al 14 first")
        #expect(read(F.sos([0], 0, 5, 0, 0) + zeros) == "damaged", "DC band 0...5 first")
        #expect(read(F.sos([0], 0, 0, 0, 2) + zeros, F.sos([0], 0, 0, 2, 0) + zeros) == "damaged", "Ah 2, Al 0 after Al 2")
        #expect(read(F.sos([0], 1, 63, 0, 0) + zeros) == "damaged", "AC before DC")
        // 8 x 8 YCbCr: after an interleaved DC first scan, an AC scan of all three (each block one EOB, 0xA0) is damaged.
        let colour = F.Frame(width: 8, height: 8, sampling: Self.samplings[0], block: F.seeded(0x99))
        let three = F.header(colour, sof: 0xC2, precision: 8, restart: 0, orientation: nil, littleEndian: false) + F.sos([0, 1, 2], 0, 0, 0, 0) + zeros
        let acOf = { (cs: [Int]) in PNGFixtures.thrown { try JPEG.read(Data(three + F.sos(cs, 1, 63, 0, 0) + [0xA0, 0xFF, 0xD9])) } }
        #expect(acOf([0]) == "returned")
        #expect(acOf([0, 1, 2]) == "damaged", "interleaved AC scan")
    }

    /// Seeded mutations of progressive codings throw a CodecError or decode, never trap or hang.
    @Test func progressiveMutationsThrowOrDecode() {
        let seeds = [F.progressive(F.Frame(width: 19, height: 9, block: F.seeded(0x94))),
                     F.progressive(F.Frame(width: 21, height: 17, sampling: Self.samplings[2], block: F.seeded(0x95))),
                     F.progressive(F.Frame(width: 24, height: 16, block: F.seeded(0x9A)), restart: 2)]
        fuzz(mutations(of: seeds, count: 600, seed: 0x1EA)) { _ = try JPEG.read($0) }
    }
}
