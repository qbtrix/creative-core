// DuplicateWalkTests.swift: the hash half of the KJ-PC walk (preview-cache
// PC-8). 50 seeded pictures, each with a half-size copy and a +0.1-stop copy,
// hash and group into exactly 50 duplicate sets of three, with no picture in
// two. The budget cases hash 1,000 seeded 256 px previews (1.5 s) and group
// 100,000 hashes, the walk's 150 among seeded random ones (2 s), printed as
// `budget <row>: <ms> ms (budget <ms> ms)`; like the other budget suites they
// run only in optimized builds. Ids are the store half's `IMG_nnnn` asset ids
// (PreviewWalkTests in CoreAssetTests).
import CoreRaster
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

/// The walk's asset id for picture `i`: `IMG_` and four digits, as in PreviewWalkTests.
private func assetID(_ i: Int) -> String {
    let digits = String(i)
    return "IMG_" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
}

/// The walk's 150 hashes, shuffled, and the 50 sets they should group into,
/// each sorted, in the order `DuplicateGroups` returns them.
private func walkHashes() throws -> (input: [(id: String, hash: PerceptualHash)], sets: [[String]]) {
    var rng = SplitMix64(seed: 817)
    var input: [(id: String, hash: PerceptualHash)] = []
    var sets: [[String]] = []
    for i in 0..<50 {
        let original = try picture(&rng)
        let copies = [(assetID(i), original),
                      (assetID(i) + "-half", try original.resized(width: 64, height: 48, filter: .bilinear)),
                      (assetID(i) + "-tone", try original.exposure(stops: 0.1))]
        for (id, buffer) in copies { input.append((id: id, hash: try PerceptualHash(of: buffer))) }
        sets.append(copies.map(\.0).sorted())
    }
    input.shuffle(using: &rng)
    return (input, sets.sorted { $0[0] < $1[0] })
}

private func milliseconds(_ d: Duration) -> String {
    let ms = Double(d.components.seconds) * 1e3 + Double(d.components.attoseconds) / 1e15
    return "\((ms * 1000).rounded() / 1000)"
}

/// Prints the median of `times` and expects it within `budget`.
private func check(_ row: String, _ times: [Duration], budget: Duration) {
    let median = times.sorted()[times.count / 2]
    print("budget \(row): \(milliseconds(median)) ms (budget \(milliseconds(budget)) ms)")
    #expect(median <= budget, "\(row): median \(median) over \(budget)")
}

@Suite(.serialized) struct DuplicateWalkTests {
    @Test func walk() throws {
        let (input, sets) = try walkHashes()
        #expect(input.count == 150 && sets.count == 50)
        let groups = DuplicateGroups.group(input, within: DuplicateGroups.maxDistance)
        #expect(groups == sets)
        let ids = groups.flatMap { $0 }
        #expect(ids.count == 150 && Set(ids).count == 150)
        // The same pictures in another order make the same groups.
        #expect(DuplicateGroups.group(input.reversed(), within: DuplicateGroups.maxDistance) == groups)
    }

    @Test(.enabled(if: optimized, "hash timing needs an optimized build"))
    func hashBudget() throws {
        var rng = SplitMix64(seed: 818)
        let previews = try (0..<1_000).map { _ in try picture(&rng, width: 256, height: 192) }
        let clock = ContinuousClock()
        var runs: [[PerceptualHash]] = []
        let times = try (0..<3).map { _ in
            var hashes: [PerceptualHash] = []
            let time = try clock.measure { hashes = try previews.map { try PerceptualHash(of: $0) } }
            runs.append(hashes)
            return time
        }
        check("hash 1000 previews 256x192", times, budget: .milliseconds(1_500))
        #expect(runs.allSatisfy { $0 == runs[0] })
        #expect(Set(runs[0]).count == previews.count)
    }

    @Test(.enabled(if: optimized, "grouping timing needs an optimized build"))
    func groupBudget() throws {
        let (walk, sets) = try walkHashes()
        var rng = SplitMix64(seed: 819)
        let input = walk + (walk.count..<100_000).map { (id: "r\($0)", hash: PerceptualHash(bits: rng.next())) }
        let clock = ContinuousClock()
        var groups: [[String]] = []
        let times = (0..<3).map { _ in clock.measure { groups = DuplicateGroups.group(input, within: DuplicateGroups.maxDistance) } }
        check("group 100000 hashes", times, budget: .seconds(2))
        // Every walk set comes out whole, and at most 1% of the random ids group.
        #expect(sets.allSatisfy(Set(groups).contains))
        #expect(groups.reduce(0) { $0 + $1.count } <= walk.count + input.count / 100)
    }
}
