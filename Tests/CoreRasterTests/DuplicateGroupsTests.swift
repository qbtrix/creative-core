// DuplicateGroupsTests.swift: DuplicateGroups puts near copies of a picture in
// one group, chains a~b~c into one group in any input order, leaves
// singletons out, counts a hash exactly `distance` away as near, clamps the
// distance to 0...16, and on seeded clusters matches a brute-force grouping
// over every pair, with each id in at most one group and a stable order.
import CoreRaster
import Testing

private func hash(_ bits: UInt64) -> PerceptualHash { PerceptualHash(bits: bits) }

/// A seeded 96 x 96 opaque picture: a 6 x 6 field of random grays and
/// colors, smoothly enlarged.
private func photo(seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    var cells = try PixelBuffer(width: 6, height: 6)
    for i in 0..<36 {
        let tone = Float.random(in: 0...1, using: &rng)
        try cells.setPixel(x: i % 6, y: i / 6, RGBA(r: tone, g: .random(in: 0...1, using: &rng), b: 1 - tone, a: 1))
    }
    return try cells.resized(width: 96, height: 96, filter: .bilinear)
}

@Test func nearCopiesFormOneGroup() throws {
    let original = try photo(seed: 701)
    let half = try original.resized(width: 48, height: 48, filter: .bilinear)
    let brighter = try original.exposure(stops: 0.1)
    let other = try photo(seed: 702)
    let input = try [("orig", original), ("half", half), ("bright", brighter), ("other", other)]
        .map { (id: $0.0, hash: try PerceptualHash(of: $0.1)) }
    #expect(DuplicateGroups.group(input, within: 8) == [["bright", "half", "orig"]])
}

// a and b are 4 apart, a and c 4 apart, b and c 8 apart: within 4 they chain
// through a whatever order they arrive in.
@Test func chainsGroup() {
    let a = (id: "a", hash: hash(0x0F)), b = (id: "b", hash: hash(0x00)), c = (id: "c", hash: hash(0xFF))
    #expect(b.hash.distance(to: c.hash) == 8)
    for order in [[a, b, c], [a, c, b], [b, a, c], [b, c, a], [c, a, b], [c, b, a]] {
        #expect(DuplicateGroups.group(order, within: 4) == [["a", "b", "c"]])
    }
}

@Test func singletonsDropped() {
    let input = [(id: "lonely", hash: hash(0)), (id: "x", hash: hash(UInt64.max)), (id: "y", hash: hash(UInt64.max))]
    #expect(DuplicateGroups.group(input, within: 2) == [["x", "y"]])
    #expect(DuplicateGroups.group([(id: "one", hash: hash(7))], within: 16) == [])
    #expect(DuplicateGroups.group([], within: 16) == [])
}

@Test func distanceIsInclusive() {
    let input = [(id: "p", hash: hash(0)), (id: "q", hash: hash(0b111))]
    #expect(DuplicateGroups.group(input, within: 3) == [["p", "q"]])
    #expect(DuplicateGroups.group(input, within: 2) == [])
}

@Test func distanceIsClamped() {
    let input = [(id: "p", hash: hash(0)), (id: "q", hash: hash(0x1_FFFF))]  // 17 apart
    #expect(DuplicateGroups.group(input, within: 16) == [])
    #expect(DuplicateGroups.group(input, within: Int.max) == [])
    #expect(DuplicateGroups.group(input, within: -1) == [])
    #expect(DuplicateGroups.group([(id: "p", hash: hash(5)), (id: "q", hash: hash(5))], within: 0) == [["p", "q"]])
    #expect(DuplicateGroups.group([(id: "p", hash: hash(5)), (id: "q", hash: hash(5))], within: Int.min) == [])
}

@Test func repeatedIdIsOnePicture() {
    let input = [(id: "p", hash: hash(0)), (id: "p", hash: hash(0xFF)), (id: "q", hash: hash(0xFE))]
    #expect(DuplicateGroups.group(input, within: 1) == [["p", "q"]])
    #expect(DuplicateGroups.group([(id: "p", hash: hash(0)), (id: "p", hash: hash(1))], within: 4) == [])
}

/// The groups by brute force: every pair within `radius` joins, repeated
/// until nothing changes, as label propagation.
private func reference(_ input: [(id: String, hash: PerceptualHash)], within radius: Int) -> Set<Set<String>> {
    var label = input.indices.map { $0 }
    var changed = true
    while changed {
        changed = false
        for i in input.indices {
            for j in input.indices where input[i].hash.distance(to: input[j].hash) <= radius && label[j] < label[i] {
                label[i] = label[j]
                changed = true
            }
        }
    }
    let sets = Dictionary(grouping: input.indices) { label[$0] }.values.map { Set($0.map { input[$0].id }) }
    return Set(sets.filter { $0.count >= 2 })
}

// Seeded clusters: 40 centers, each with up to 5 copies a few bits off, plus
// lone hashes; every radius 0...16 against the brute force.
@Test func matchesBruteForceOnSeededClusters() {
    var rng = SplitMix64(seed: 703)
    var input: [(id: String, hash: PerceptualHash)] = []
    for center in 0..<40 {
        let bits = rng.next()
        for copy in 0..<Int.random(in: 1...5, using: &rng) {
            var flipped = bits
            for _ in 0..<Int.random(in: 0...6, using: &rng) { flipped ^= 1 << UInt64.random(in: 0..<64, using: &rng) }
            input.append((id: "c\(center)-\(copy)", hash: hash(flipped)))
        }
    }
    input.shuffle(using: &rng)
    for radius in 0...DuplicateGroups.maxDistance {
        let groups = DuplicateGroups.group(input, within: radius)
        let ids = groups.flatMap { $0 }
        #expect(Set(ids).count == ids.count)
        #expect(groups.allSatisfy { $0 == $0.sorted() && $0.count >= 2 })
        #expect(groups.map { $0[0] } == groups.map { $0[0] }.sorted())
        #expect(Set(groups.map(Set.init)) == reference(input, within: radius))
        #expect(DuplicateGroups.group(input.reversed(), within: radius) == groups)
    }
}
