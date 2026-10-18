// DuplicateGroups.swift: groups pictures whose PerceptualHash values lie
// within a distance of each other, transitively: a~b and b~c put a, b and c
// in one group even when a and c are far apart. Invariants: each id lands in
// at most one group; groups of one are left out; each group is sorted by id
// and the list by its first id, so the same input gives the same output. The
// distance is clamped to 0...16 (a negative one groups nothing): beyond 16
// unrelated pictures (about 32 apart) start to chain. Equal hashes join at
// once; the distinct ones go into a BK-tree, each queried before it is
// inserted, so every near pair is found once and joined in a union-find.
// Ids repeated in the input are one picture.

/// Groups of near-duplicate pictures by perceptual hash.
public enum DuplicateGroups {
    /// The largest distance `group` honours; larger ones are clamped to it.
    public static let maxDistance = 16

    /// The ids of `hashes` grouped by chains of hashes at most `distance`
    /// apart (clamped to 0...16), groups of two or more only, each sorted by
    /// id and the list sorted by first id.
    public static func group(_ hashes: [(id: String, hash: PerceptualHash)], within distance: Int) -> [[String]] {
        guard distance >= 0 else { return [] }
        let radius = min(distance, maxDistance)
        var ids: [String] = []
        var index: [String: Int] = [:]
        var sets = UnionFind()
        var holder: [UInt64: Int] = [:]
        var tree = BKTree()
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
                continue
            }
            holder[bits] = me
            for node in tree.near(bits, within: radius) {
                if let other = holder[tree.bits[node]] { sets.union(me, other) }
            }
            tree.insert(bits)
        }
        var byRoot: [Int: [String]] = [:]
        for (i, id) in ids.enumerated() { byRoot[sets.root(i), default: []].append(id) }
        let groups = byRoot.values.filter { $0.count >= 2 }.map { $0.sorted() }
        return groups.sorted { ($0.first ?? "") < ($1.first ?? "") }
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

/// A BK-tree of distinct 64-bit hashes under Hamming distance. Each child
/// hangs off its parent by their distance (1...64), so a query within `r` of
/// `q` only descends edges in `d - r ... d + r`, where `d` is the parent's
/// distance to `q` (the triangle inequality). Walks use an explicit stack.
private struct BKTree {
    private(set) var bits: [UInt64] = []
    private var children: [[Int: Int]] = []

    mutating func insert(_ value: UInt64) {
        let new = bits.count
        bits.append(value)
        children.append([:])
        guard new > 0 else { return }
        var node = 0
        while true {
            let d = (bits[node] ^ value).nonzeroBitCount
            guard d > 0 else { return }
            if let next = children[node][d] {
                node = next
            } else {
                children[node][d] = new
                return
            }
        }
    }

    /// The nodes whose hash is at most `radius` bits from `value`.
    func near(_ value: UInt64, within radius: Int) -> [Int] {
        guard !bits.isEmpty else { return [] }
        var found: [Int] = []
        var stack = [0]
        while let node = stack.popLast() {
            let d = (bits[node] ^ value).nonzeroBitCount
            if d <= radius { found.append(node) }
            for (edge, child) in children[node] where edge >= d - radius && edge <= d + radius {
                stack.append(child)
            }
        }
        return found
    }
}
