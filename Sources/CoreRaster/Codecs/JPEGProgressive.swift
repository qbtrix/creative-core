// JPEGProgressive.swift: JPEG.read's progressive scans (ITU-T T.81 Annex G,
// decoded as G.2 describes): DC first and DC refinement scans, AC spectral
// selection first scans with end-of-band runs, and AC successive
// approximation refinement, into the coefficient store `pixels()` shares
// with the sequential scan. Invariants: each scan's band and approximation
// are checked (B.2.3, G.1.1.1) against what earlier scans coded before any
// bit is read; EOBRUN and the DC predictions reset at each restart interval;
// the scans together walk at most `passes` times the frame's blocks.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension JPEGDecoder {
    /// The most block visits all progressive scans may make, in passes over every block of the frame. A scan header is
    /// a few bytes and an EOB run skips 32767 blocks in two more, so bytes do not bound the work; real encoders send
    /// under 20 scans, Annex G's limits allow 896 per component.
    static let passes = 64

    /// One progressive scan; `coded` holds per component and zigzag index the Al that last coded it, or -1, then
    /// one row of the blocks walked so far.
    mutating func progressiveScan(_ scan: JPEGScan, _ intervals: [[UInt8]], _ coded: inout [[Int]]) throws {
        try check(scan, &coded)
        var pred = [Int32](repeating: 0, count: scan.parts.count), eobrun = 0
        try walk(scan, intervals, restart: { pred = pred.map { _ in 0 }; eobrun = 0 }) { bits, j, store, base in
            if scan.ss == 0, scan.ah > 0 { store[base] |= bits.bits(1) << scan.al; return }
            guard let table = scan.ss == 0 ? scan.parts[j].dc : scan.parts[j].ac else { throw CodecError.damaged("no DHT \(scan.ss == 0 ? "DC" : "AC") table") }
            switch (scan.ss, scan.ah) {
            case (0, _): try bits.dcFirst(table, scan.al, &pred[j], &store, base)
            case (_, 0): try bits.acFirst(table, scan, &eobrun, &store, base)
            default: try bits.acRefine(table, scan, &eobrun, &store, base)
            }
        }
    }

    /// B.2.3 and G.1.1.1: ss <= se <= 63, a DC scan codes only coefficient 0, an AC scan one component whose DC is
    /// coded, Al <= 13, a first scan codes coefficients not yet coded and a refinement those last coded at Al = Ah - 1;
    /// `tooLarge` once the scans would walk over `passes` times the frame's blocks.
    func check(_ scan: JPEGScan, _ coded: inout [[Int]]) throws {
        guard let f = frame else { throw CodecError.damaged("SOS before SOF") }
        let n = f.components.count
        if coded.count != n + 1 { coded = f.components.map { _ in [Int](repeating: -1, count: 64) } + [[0]] }
        let (ss, se, ah, al) = (scan.ss, scan.se, scan.ah, scan.al)
        guard ss <= se, se <= 63 else { throw CodecError.damaged("scan band \(ss)...\(se): a band must run up within 0...63") }
        guard al <= 13 else { throw CodecError.damaged("scan Al \(al): a scan's Al must be 0...13") }
        guard ss == 0 ? se == 0 : scan.parts.count == 1 else {
            throw CodecError.damaged(ss == 0 ? "DC scan band 0...\(se): a DC scan must have se 0"
                                             : "AC scan of \(scan.parts.count) components: an AC scan must code one component")
        }
        guard ah == 0 || ah == al + 1 else { throw CodecError.damaged("refinement scan at Ah \(ah), Al \(al): a refinement must have Al = Ah - 1") }
        for part in scan.parts {
            guard part.index < n else { throw CodecError.damaged("scan names component index \(part.index), past the frame's \(n) components") }
            let want = ah == 0 ? -1 : ah
            guard ss == 0 || coded[part.index][0] >= 0, coded[part.index][ss...se].allSatisfy({ $0 == want }) else {
                throw CodecError.damaged("component \(f.components[part.index].id) coefficients \(ss)...\(se) out of order")
            }
            for k in ss...se { coded[part.index][k] = al }
        }
        // Sides are at most maxSide and factors 4, so neither sum can overflow.
        let blocks = f.components.reduce(0) { $0 + $1.stride * $1.rows }, walked = scan.parts.reduce(coded[n].first ?? 0) {
            let c = f.components[$1.index]
            return $0 + (scan.parts.count == 1 ? c.blocksX * c.blocksY : c.stride * c.rows)
        }
        guard walked <= Self.passes * blocks else { throw CodecError.tooLarge("progressive scans revisit the \(blocks) blocks more than \(Self.passes) times") }
        coded[n] = [walked]
    }
}

extension JPEGBits {
    /// `n` bits (0...16) as an unsigned value.
    mutating func bits(_ n: Int) -> Int32 {
        guard n > 0 else { return 0 }
        let v = Int32(peek(n))
        skip(n)
        return v
    }

    /// G.1.2.1: a DC first scan's difference added to the prediction, the sum scaled by 2^Al.
    mutating func dcFirst(_ dc: JPEGHuffman, _ al: Int, _ pred: inout Int32, _ store: inout [Int32], _ base: Int) throws {
        let s = try symbol(dc)
        guard s <= 15 else { throw CodecError.damaged("DC size \(s) is over 15") }
        pred = pred &+ receive(s)
        store[base] = pred << al
    }

    /// G.1.2.2: band ss...se of one block as run/size symbols scaled by 2^Al; EOBn (run 2^n + n bits) ends this block
    /// and the next EOBRUN - 1 blocks of the band, which read nothing.
    mutating func acFirst(_ ac: JPEGHuffman, _ scan: JPEGScan, _ eobrun: inout Int, _ store: inout [Int32], _ base: Int) throws {
        guard eobrun == 0 else { eobrun -= 1; return }
        var k = scan.ss
        while k <= scan.se {
            let rs = try symbol(ac), r = rs >> 4, s = rs & 15
            if s == 0 {
                guard r == 15 else { eobrun = (1 << r) - 1 + Int(bits(r)); return }
                k += 16
                continue
            }
            k += r
            guard k <= scan.se else { throw CodecError.damaged("AC run past coefficient \(scan.se)") }
            store[base + JPEGDecoder.zigzag[k]] = receive(s) << scan.al
            k += 1
        }
    }

    /// G.1.2.3: one more bit at Al of band ss...se. A symbol (R, 1) and its sign bit place a new ±2^Al at the R+1th
    /// coefficient still zero; every non-zero one passed on the way, or left in an end-of-band run, takes a correction
    /// bit that adds 2^Al to its magnitude.
    mutating func acRefine(_ ac: JPEGHuffman, _ scan: JPEGScan, _ eobrun: inout Int, _ store: inout [Int32], _ base: Int) throws {
        let one = Int32(1) << scan.al
        var k = scan.ss
        func correct(_ v: inout Int32) { if bits(1) == 1, v & one == 0 { v += v > 0 ? one : -one } }
        while eobrun == 0, k <= scan.se {
            let rs = try symbol(ac), s = rs & 15
            var r = rs >> 4, value: Int32 = 0
            if s == 0, r < 15 { eobrun = (1 << r) + Int(bits(r)); break }
            if s != 0 {
                guard s == 1 else { throw CodecError.damaged("refinement symbol size \(s): an AC refinement codes size 0 or 1") }
                value = bits(1) == 1 ? one : -one
            }
            while k <= scan.se {
                let z = base + JPEGDecoder.zigzag[k]
                k += 1
                if store[z] != 0 { correct(&store[z]); continue }
                if r == 0 { store[z] = value; break }
                r -= 1
            }
        }
        guard eobrun > 0 else { return }
        while k <= scan.se {
            let z = base + JPEGDecoder.zigzag[k]
            if store[z] != 0 { correct(&store[z]) }
            k += 1
        }
        eobrun -= 1
    }
}
