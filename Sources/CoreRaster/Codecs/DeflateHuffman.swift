// DeflateHuffman.swift: one block of Deflate's LZ77 symbols (RFC 1951, 3.2.4
// to 3.2.7), stored, fixed or dynamic Huffman, whichever takes the fewest bits.
// Invariants: deterministic (ties break by symbol); every dynamic code complete
// and within 15 bits (7 for the code-length code), lengths run-length coded.
extension Deflate {
    /// RFC 1951 3.2.5: the length code (0...28) of each length 0...258, the distance code of each distance 0...32,768.
    static let lengthSymbol: [UInt8] = (0...258).map { l in UInt8(Inflate.lengthBase.lastIndex { $0 <= l } ?? 0) }
    static let distanceSymbol: [UInt8] = (0...32_768).map { d in UInt8(Inflate.distBase.lastIndex { $0 <= d } ?? 0) }
    /// 3.2.6: the fixed literal/length and distance code lengths.
    static let fixedLit: [UInt8] = (0..<288).map { $0 < 144 ? 8 : $0 < 256 ? 9 : $0 < 280 ? 7 : 8 }
    static let fixedDist = [UInt8](repeating: 5, count: 30)

    /// Writes `symbols`, which cover `bytes`, as one block: stored, fixed or dynamic, whichever is shortest.
    static func block(_ symbols: [UInt32], _ bytes: [UInt8], final: Bool, into writer: inout BitWriter) {
        var lit = [Int](repeating: 0, count: 286), dist = [Int](repeating: 0, count: 30), extra = 0
        for s in symbols {
            if s < 256 { lit[Int(s)] += 1; continue }
            let l = Int(lengthSymbol[Int(s & 511)]), d = Int(distanceSymbol[Int(s >> 9)])
            (lit[257 + l], dist[d]) = (lit[257 + l] + 1, dist[d] + 1)
            extra += Inflate.lengthExtra[l] + Inflate.distExtra[d]
        }
        lit[256] = 1
        let litLengths = huffmanLengths(lit, limit: 15), distLengths = huffmanLengths(dist, limit: 15)
        let header = DynamicHeader(litLengths, distLengths)
        func bits(_ ll: [UInt8], _ dl: [UInt8]) -> Int {
            zip(lit, ll).reduce(3 + extra) { $0 + $1.0 * Int($1.1) } + zip(dist, dl).reduce(0) { $0 + $1.0 * Int($1.1) }
        }
        let fixed = bits(fixedLit, fixedDist), dynamic = header.bits + bits(litLengths, distLengths)
        guard (bytes.count / 65_535 + 1) * 40 + bytes.count * 8 >= min(fixed, dynamic) else { return stored(bytes, final: final, into: &writer) }
        let dynamicWins = dynamic < fixed
        writer.put((final ? 1 : 0) | (dynamicWins ? 4 : 2), 3)
        if dynamicWins { header.write(into: &writer) }
        emit(symbols, dynamicWins ? litLengths : fixedLit, dynamicWins ? distLengths : fixedDist, into: &writer)
    }

    /// The symbols, then end of block, in the codes these lengths give.
    static func emit(_ symbols: [UInt32], _ litLengths: [UInt8], _ distLengths: [UInt8], into writer: inout BitWriter) {
        let litCodes = codes(litLengths), distCodes = codes(distLengths)
        for s in symbols {
            if s < 256 { writer.put(litCodes[Int(s)], Int(litLengths[Int(s)])); continue }
            let length = Int(s & 511), distance = Int(s >> 9), l = Int(lengthSymbol[length]), d = Int(distanceSymbol[distance])
            writer.put(litCodes[257 + l], Int(litLengths[257 + l])); writer.put(length - Inflate.lengthBase[l], Inflate.lengthExtra[l])
            writer.put(distCodes[d], Int(distLengths[d])); writer.put(distance - Inflate.distBase[d], Inflate.distExtra[d])
        }
        writer.put(litCodes[256], Int(litLengths[256]))
    }

    /// 3.2.2's canonical codes for `lengths` (each 0...15), bit-reversed for `BitWriter.put`.
    static func codes(_ lengths: [UInt8]) -> [Int] {
        var count = [Int](repeating: 0, count: 16), next = count, result = [Int](repeating: 0, count: lengths.count)
        for length in lengths where length > 0 { count[Int(length)] += 1 }
        for bits in 1...15 { next[bits] = (next[bits - 1] + count[bits - 1]) << 1 }
        for (symbol, raw) in lengths.enumerated() where raw > 0 {
            let length = Int(raw)
            for bit in 0..<length { result[symbol] |= (next[length] >> bit & 1) << (length - 1 - bit) }
            next[length] += 1
        }
        return result
    }

    /// Huffman code lengths for `freq`, none over `limit` bits; fewer than two used symbols get partners
    /// (0, then 1). Ties break by symbol, and a more frequent symbol never gets a longer code.
    static func huffmanLengths(_ freq: [Int], limit: Int) -> [UInt8] {
        var leaves = freq.indices.filter { freq[$0] > 0 }
        for s in 0..<2 where leaves.count < 2 && !leaves.contains(s) { leaves.append(s) }
        leaves.sort { (freq[$0], $0) < (freq[$1], $1) }
        let n = leaves.count
        var weight = leaves.map { freq[$0] }, parent = [Int](repeating: 0, count: 2 * n - 1), leaf = 0, node = n
        for joined in n..<(2 * n - 1) {
            var sum = 0; for _ in 0..<2 {
                let pick: Int
                if leaf < n, node >= joined || weight[leaf] <= weight[node] { (pick, leaf) = (leaf, leaf + 1) } else { (pick, node) = (node, node + 1) }
                (parent[pick], sum) = (joined, sum + weight[pick])
            }
            weight.append(sum)
        }
        var depth = [Int](repeating: 0, count: 2 * n - 1), count = [Int](repeating: 0, count: limit + 1)
        for k in stride(from: 2 * n - 3, through: 0, by: -1) { depth[k] = depth[parent[k]] + 1 }
        for k in 0..<n { count[min(depth[k], limit)] += 1 }
        var kraft = (1...limit).reduce(0) { $0 + count[$1] << (limit - $1) }
        while kraft > 1 << limit {
            (count[limit], kraft) = (count[limit] - 1, kraft - 1)
            if let l = (1..<limit).last(where: { count[$0] > 0 }) { (count[l], count[l + 1]) = (count[l] - 1, count[l + 1] + 2) }
        }
        var lengths = [UInt8](repeating: 0, count: freq.count), k = n
        for length in 1...limit { for _ in 0..<count[length] { k -= 1; lengths[leaves[k]] = UInt8(length) } }
        return lengths
    }

    /// 3.2.7's header: HLIT, HDIST, HCLEN, the code-length code, then both codes' lengths run-length coded,
    /// each run a symbol | extra << 5. `bits` counts the header and block type bits.
    struct DynamicHeader {
        var hlit = 286, hdist = 30, hclen = 19, runs: [Int] = [], codeLengths: [UInt8] = [], bits = 0
        static func extraBits(_ symbol: Int) -> Int { symbol < 16 ? 0 : symbol == 16 ? 2 : symbol == 17 ? 3 : 7 }
        init(_ lit: [UInt8], _ dist: [UInt8]) {
            while hlit > 257, lit[hlit - 1] == 0 { hlit -= 1 }
            while hdist > 1, dist[hdist - 1] == 0 { hdist -= 1 }
            let all = Array(lit[0..<hlit] + dist[0..<hdist]); var i = 0
            while i < all.count {
                let value = Int(all[i]); var run = 1
                while i + run < all.count, all[i + run] == all[i] { run += 1 }
                i += run
                if value != 0 { runs.append(value); run -= 1 }
                while run >= 3 {
                    let k = min(run, value == 0 ? 138 : 6)
                    runs.append(value != 0 ? 16 | (k - 3) << 5 : k >= 11 ? 18 | (k - 11) << 5 : 17 | (k - 3) << 5)
                    run -= k
                }
                runs += repeatElement(value, count: run)
            }
            var freq = [Int](repeating: 0, count: 19); for r in runs { freq[r & 31] += 1 }
            codeLengths = Deflate.huffmanLengths(freq, limit: 7)
            while hclen > 4, codeLengths[Inflate.order[hclen - 1]] == 0 { hclen -= 1 }
            bits = 14 + 3 * hclen + runs.reduce(0) { $0 + Int(codeLengths[$1 & 31]) + Self.extraBits($1 & 31) }
        }

        func write(into writer: inout BitWriter) {
            writer.put(hlit - 257 | (hdist - 1) << 5 | (hclen - 4) << 10, 14)
            for k in 0..<hclen { writer.put(Int(codeLengths[Inflate.order[k]]), 3) }
            let codes = Deflate.codes(codeLengths)
            for r in runs { writer.put(codes[r & 31], Int(codeLengths[r & 31])); writer.put(r >> 5, Self.extraBits(r & 31)) }
        }
    }
}
