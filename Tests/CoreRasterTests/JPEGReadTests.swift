// JPEGReadTests.swift: JPEG.info and JPEG.read against JPEGs built from
// ITU-T T.81, JFIF 1.02 and EXIF 2.3 (JPEGFixtures), each within a mean of
// 1/255 and a maximum of 4/255 of its A.3.3 reference: grey and YCbCr at
// 4:4:4, 4:2:2 and 4:2:0, the zigzag order, restart intervals, the EXIF
// orientation reported but not applied, and unsupported, oversized or
// damaged files refused. Disabled until IC-6 (baseline).
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

    @Test(.disabled("waits on IC-6")) func infoReadsFrame() throws {
        let colour = F.Frame(width: 37, height: 21, sampling: Self.samplings[2], block: F.seeded(0x1F))
        #expect(try JPEG.info(F.baseline(colour)) == JPEGInfo(width: 37, height: 21, components: 3, progressive: false, orientation: 1))
        #expect(try JPEG.info(F.stub(colour, sof: 0xC2)).progressive)
        let tall = F.Frame(width: 1, height: JPEG.maxSide, block: F.seeded(0))
        #expect(try JPEG.info(F.stub(tall)) == JPEGInfo(width: 1, height: JPEG.maxSide, components: 1, progressive: false, orientation: 1))
    }

    /// DC only, the inverse DCT is flat: S00 = 16q (K.1) gives samples 128 + 2q (A.3.3, C(0)² = 1/2).
    @Test(.disabled("waits on IC-6")) func greyDCOnly() throws {
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
    @Test(.disabled("waits on IC-6")) func zigzag() throws {
        let flat = [Int](repeating: 16, count: 64)
        let f = F.Frame(width: 64, height: 64, tables: [flat, flat], block: { _, x, y in
            var q = [Int](repeating: 0, count: 64), k = y * 8 + x
            q[0] = k - 32
            if k > 0 { q[F.zigzag[k]] = k % 2 == 0 ? 4 : -4 }
            return q
        })
        try check(f, F.baseline(f), "one coefficient per block")
    }

    @Test(.disabled("waits on IC-6")) func ycbcrSampling() throws {
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
    @Test(.disabled("waits on IC-6")) func restartResetsDC() throws {
        let grey = F.Frame(width: 80, height: 16, block: F.seeded(0x71))
        for n in [1, 3] { try check(grey, F.baseline(grey, restart: n), "grey every \(n)") }
        let colour = F.Frame(width: 48, height: 40, sampling: Self.samplings[2], block: F.seeded(0x72))
        for n in [1, 2, 4] { try check(colour, F.baseline(colour, restart: n), "4:2:0 every \(n)") }
        #expect(try JPEG.read(F.baseline(colour, restart: 2)) == JPEG.read(F.baseline(colour)))
    }

    @Test(.disabled("waits on IC-6")) func exifOrientation() throws {
        let f = F.Frame(width: 13, height: 7, sampling: Self.samplings[1], block: F.seeded(0x0E))
        let plain = try JPEG.read(F.baseline(f))
        for (orientation, little) in [(6, false), (8, true), (3, false), (1, true)] {
            let data = F.baseline(f, orientation: orientation, littleEndian: little)
            #expect(try JPEG.info(data) == JPEGInfo(width: 13, height: 7, components: 3, progressive: false, orientation: orientation))
            #expect(try JPEG.read(data) == plain, "pixels are not rotated")
        }
    }

    /// Arithmetic coding (SOF9, SOF10), lossless (SOF3) and hierarchical (SOF5) frames, 12-bit samples and four components.
    @Test(.disabled("waits on IC-6")) func unsupportedThrows() throws {
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
    @Test(.disabled("waits on IC-6")) func refusesHuge() throws {
        for (width, height) in [(JPEG.maxSide + 1, 1), (1, JPEG.maxSide + 1), (20_000, 20_000)] {
            for sampling in [[(1, 1)], Self.samplings[2]] {
                let data = F.stub(F.Frame(width: width, height: height, sampling: sampling, block: F.seeded(0)))
                #expect(PNGFixtures.thrown { try JPEG.read(data) } == "tooLarge", "\(width)x\(height)")
                let overSide = width > JPEG.maxSide || height > JPEG.maxSide
                #expect(PNGFixtures.thrown { try JPEG.info(data) } == (overSide ? "tooLarge" : "returned"))
            }
        }
        #expect(PNGFixtures.thrown { try JPEG.read(F.stub(F.Frame(width: JPEG.maxSide, height: 1, block: F.seeded(0)))) } == "damaged")
    }

    @Test(.disabled("waits on IC-6")) func damagedThrows() throws {
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
        for data in [without { m, _ in m == 0xC0 }, Data([0xFF, 0xD8, 0xFF, 0xE0, 0xFF, 0xF0, 0x4A, 0x46])] {
            #expect(PNGFixtures.thrown { try JPEG.info(data) } == "damaged", "no SOF, or a segment past the end")
            #expect(PNGFixtures.thrown { try JPEG.read(data) } == "damaged")
        }
        #expect(PNGFixtures.thrown { try JPEG.info(good.dropFirst()) } == "notThisFormat")
        #expect(PNGFixtures.thrown { try JPEG.read(Data(PNGFixtures.signature)) } == "notThisFormat")
    }
}
