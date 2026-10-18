// DuplicateGroups.swift: groups pictures whose PerceptualHash values lie
// within a distance of each other, transitively: a~b and b~c put a, b and c
// in one group even when a and c are far apart. Invariants: each id lands in
// at most one group; groups of one are left out; each group is sorted by id
// and the list by its first id, so the same input gives the same output. The
// distance is clamped to 0...10 (a negative one groups nothing): past it
// unrelated hashes start to chain. Of 100,000 seeded random hashes, 0.1% of the
// ids land in groups at 10, 0.5% at 11, 2% at 12, 29% at 14 and 98% at 16.
// Equal hashes join at once. The distinct ones go into a multi-index table:
// the 64 bits split into four 16-bit blocks. Writing r = 4q + a (a < 4), two
// hashes within r must have one of blocks 0...a within q or one of the rest
// within q - 1, else they differ in (a + 1)(q + 1) + (3 - a)q = r + 1 bits
// (pigeonhole). Each block's table holds the hashes sorted by that block, in
// input order within one run per key, so hash i reads the runs of the keys
// near its own block, up to the first hash at or after i, and checks the full
// distance of each one there: every near pair is found from its later hash
// and joined in a union-find. Ids repeated in the input are one picture.

/// Groups of near-duplicate pictures by perceptual hash.
public enum DuplicateGroups {
    /// The largest distance `group` honours; larger ones are clamped to it.
    public static let maxDistance = 10

    /// The ids of `hashes` grouped by chains of hashes at most `distance`
    /// apart (clamped to 0...10), groups of two or more only, each sorted by
    /// id and the list sorted by first id.
    public static func group(_ hashes: [(id: String, hash: PerceptualHash)], within distance: Int) -> [[String]] {
        guard distance >= 0 else { return [] }
        let radius = min(distance, maxDistance)
        var ids: [String] = []
        var index: [String: Int] = [:]
        var sets = UnionFind()
        var holder: [UInt64: Int] = [:]
        var distinct: [UInt64] = []
        var owners: [Int] = []
        for entry in hashes {
            let me: Int
            if let known = index[entry.id] {
                me = known
            } else {
                me = ids.count
                index[entry.id] = me
                ids.append(entry.id)
                sets.add()
            }
            let bits = entry.hash.bits
            if let other = holder[bits] {
                sets.union(me, other)
            } else {
                holder[bits] = me
                distinct.append(bits)
                owners.append(me)
            }
        }
        let table = BlockIndex(distinct, radius: radius)
        table.forEachNearPair { sets.union(owners[$0], owners[$1]) }
        var byRoot: [Int: [String]] = [:]
        for (i, id) in ids.enumerated() { byRoot[sets.root(i), default: []].append(id) }
        let groups = byRoot.values.filter { $0.count >= 2 }.map { $0.sorted() }
        return groups.sorted { ($0.first ?? "") < ($1.first ?? "") }
    }
}

/// Distinct 64-bit hashes indexed by each of their four 16-bit blocks. For
/// block `b`, `bits[b]` and `entries[b]` hold every hash and its index sorted
/// by that block (a counting sort, so each run keeps input order), and the
/// run of key `k` is `starts[b][k] ..< starts[b][k + 1]`.
private struct BlockIndex {
    private static let blocks = 4
    private static let keys = 1 << 16
    private let radius: Int
    /// The flip patterns each block probes: every 16-bit pattern of at most
    /// q bits for blocks 0...a, at most q - 1 for the rest (none when q = 0).
    private var flips: [[Int]] = []
    private var starts: [[Int]] = []
    private var bits: [[UInt64]] = []
    private var entries: [[Int]] = []

    init(_ values: [UInt64], radius: Int) {
        self.radius = radius
        let q = radius / Self.blocks, a = radius % Self.blocks
        let wide = (0..<Self.keys).filter { $0.nonzeroBitCount <= q }
        let narrow = wide.filter { $0.nonzeroBitCount < q }
        for b in 0..<Self.blocks {
            flips.append(b <= a ? wide : narrow)
            var start = Array(repeating: 0, count: Self.keys + 1)
            for value in values { start[Self.key(value, block: b) + 1] += 1 }
            for k in 0..<Self.keys { start[k + 1] += start[k] }
            var fill = start
            var sortedBits = Array(repeating: UInt64(0), count: values.count)
            var sortedEntries = Array(repeating: 0, count: values.count)
            for (i, value) in values.enumerated() {
                let k = Self.key(value, block: b)
                sortedBits[fill[k]] = value
                sortedEntries[fill[k]] = i
                fill[k] += 1
            }
            starts.append(start)
            bits.append(sortedBits)
            entries.append(sortedEntries)
        }
    }

    /// Block `b` of `value`, a key in 0..<65,536.
    private static func key(_ value: UInt64, block b: Int) -> Int {
        Int(truncatingIfNeeded: (value >> UInt64(16 * b)) & 0xFFFF)
    }

    /// Calls `body` with `(i, j)` for every pair of hashes at most `radius`
    /// bits apart with j earlier than i, once per block whose probe finds it.
    /// Each block's probes run one flip at a time over the hashes in key
    /// order, so the runs they read move through memory in step.
    func forEachNearPair(_ body: (Int, Int) -> Void) {
        for b in 0..<Self.blocks {
            let start = starts[b], run = bits[b], index = entries[b]
            for flip in flips[b] {
                for p in run.indices {
                    let value = run[p], i = index[p]
                    let k = Self.key(value, block: b) ^ flip
                    var j = start[k]
                    let end = start[k + 1]
                    while j < end && index[j] < i {
                        if (run[j] ^ value).nonzeroBitCount <= radius { body(i, index[j]) }
                        j += 1
                    }
                }
            }
        }
    }
}

/// Disjoint sets over 0..<count, by size, with path compression.
private struct UnionFind {
    private var parent: [Int] = []
    private var size: [Int] = []

    mutating func add() {
        parent.append(parent.count)
        size.append(1)
    }

    mutating func root(_ x: Int) -> Int {
        var top = x
        while parent[top] != top { top = parent[top] }
        var walk = x
        while parent[walk] != top {
            let next = parent[walk]
            parent[walk] = top
            walk = next
        }
        return top
    }

    mutating func union(_ a: Int, _ b: Int) {
        var big = root(a), small = root(b)
        guard big != small else { return }
        if size[big] < size[small] { swap(&big, &small) }
        parent[small] = big
        size[big] += size[small]
    }
}
