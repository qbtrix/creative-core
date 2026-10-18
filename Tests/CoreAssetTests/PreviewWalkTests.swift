// PreviewWalkTests.swift: the store half of the KJ-PC walk (preview-cache
// PC-8). A store in a scratch folder takes 2,000 previews over the three size
// classes, 600 of them on volume "Card A"; a relaunched store reads every one
// back equal; with Card A unplugged its 600 entries still read and report
// offline; reopened at half the budget, the next write evicts the least
// recently read half and the rest still read. Every write rewrites the whole
// index, so filling is quadratic: debug builds walk 200 previews (60 on Card
// A), as DuplicateGroupsTests' budget walks 10,000 there. The budget cases
// fill 2,000 and time a relaunch that reads their index (40 ms) and a cached
// read (0.3 ms) as medians, printed as `budget <row>: <ms> ms (budget <ms>
// ms)`; like the other budget suites they run only in optimized builds, since
// debug timings on a loaded machine prove nothing. The hash half is
// DuplicateWalkTests in CoreRasterTests, joined by the `IMG_nnnn` asset ids.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreAsset
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

/// The previews the budget cases fill, and the walk in an optimized build.
private let previewCount = 2_000
private let walkCount = optimized ? previewCount : 200
/// Every payload is this long, so half the budget keeps exactly half the previews.
private let payloadBytes = 256
private let cardA = VolumeRef(id: "vol-card-a", name: "Card A")
private let studioDisk = VolumeRef(id: "vol-studio", name: "Studio Disk")

/// The walk's asset id for picture `i`: `IMG_` and four digits, as in DuplicateWalkTests.
private func assetID(_ i: Int) -> String {
    let digits = String(i)
    return "IMG_" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
}

private struct WalkPreview {
    let key: PreviewKey
    let bytes: Data
    let volume: VolumeRef
}

/// `count` seeded previews: size classes in turn, three in ten on Card A.
private func walkPreviews(_ count: Int) -> [WalkPreview] {
    (0..<count).map { i in
        var rng = SplitMix64(state: UInt64(i))
        let bytes = Data((0..<payloadBytes).map { _ in UInt8.random(in: 0...255, using: &rng) })
        return WalkPreview(key: PreviewKey(asset: assetID(i), content: "sha-\(i)", size: SizeClass.allCases[i % 3]),
                           bytes: bytes, volume: i % 10 < 3 ? cardA : studioDisk)
    }
}

/// Writes `count` previews into a store on `folder` and closes it.
private func fill(_ folder: URL, count: Int) throws -> [WalkPreview] {
    let previews = walkPreviews(count)
    let store = try ThumbnailStore(folder: folder, budgetBytes: count * payloadBytes)
    for p in previews {
        try store.write(p.bytes, for: p.key, volume: p.volume, relativePath: "DCIM/\(p.key.asset).jpg")
    }
    return previews
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

@Suite(.serialized) struct PreviewWalkTests {
    @Test func walk() throws {
        let scratch = try PreviewScratch()
        let previews = try fill(scratch.folder, count: walkCount)
        let totalBytes = walkCount * payloadBytes
        #expect(try scratch.previewFiles().count == walkCount)
        var rng = SplitMix64(state: 816)
        let order = previews.indices.shuffled(using: &rng)
        let onCard = order.filter { previews[$0].volume == cardA }
        do {
            // Relaunch: a second store on the folder reads every preview back equal.
            let relaunched = try ThumbnailStore(folder: scratch.folder, budgetBytes: totalBytes)
            #expect(relaunched.usedBytes == totalBytes)
            #expect(try order.filter { try relaunched.read(previews[$0].key) != previews[$0].bytes } == [])

            // Card A unplugged: its 600 entries still read and report offline.
            let mounted: Set<String> = [studioDisk.id]
            #expect(onCard.count == walkCount * 3 / 10)
            #expect(Set(relaunched.entries(on: cardA).map(\.key)) == Set(onCard.map { previews[$0].key }))
            #expect(relaunched.entries(on: VolumeRef(id: cardA.id, name: "Renamed")).count == onCard.count)
            #expect(try onCard.filter { try relaunched.read(previews[$0].key) != previews[$0].bytes } == [])
            #expect(onCard.filter { relaunched.availability(of: previews[$0].key, mounted: mounted) != .offline(cardA) } == [])
            #expect(order.filter { previews[$0].volume == studioDisk && relaunched.availability(of: previews[$0].key, mounted: mounted) != .online } == [])
            #expect(relaunched.availability(of: PreviewKey(asset: "IMG_9999", content: "none", size: .small), mounted: mounted) == nil)
        }

        // Read once in `order`, then Card A again: that is the recency, oldest first.
        let recency = order.filter { previews[$0].volume != cardA } + onCard
        let smaller = try ThumbnailStore(folder: scratch.folder, budgetBytes: totalBytes / 2)
        #expect(smaller.usedBytes == totalBytes)  // opening never evicts
        // Half the budget: the next write (the newest preview, rewritten) evicts.
        let newest = try #require(recency.last.map { previews[$0] })
        try smaller.write(newest.bytes, for: newest.key, volume: newest.volume, relativePath: "DCIM/\(newest.key.asset).jpg")
        #expect(smaller.usedBytes == totalBytes / 2)
        #expect(try scratch.previewFiles().count == walkCount / 2)
        let gone = recency.prefix(walkCount / 2), kept = recency.suffix(walkCount / 2)
        #expect(try gone.filter { try smaller.read(previews[$0].key) != nil } == [])
        #expect(try kept.filter { try smaller.read(previews[$0].key) != previews[$0].bytes } == [])
        #expect(smaller.entries(on: cardA).count == onCard.count)  // read last, so all kept
    }

    @Test(.enabled(if: optimized, "relaunch timing needs an optimized build"))
    func relaunchBudget() throws {
        let scratch = try PreviewScratch()
        let previews = try fill(scratch.folder, count: previewCount)
        let totalBytes = previewCount * payloadBytes
        let clock = ContinuousClock()
        var stores: [ThumbnailStore] = []
        let times = try (0..<11).map { _ in
            var store: ThumbnailStore?
            let time = try clock.measure { store = try ThumbnailStore(folder: scratch.folder, budgetBytes: totalBytes) }
            if let store { stores.append(store) }
            return time
        }
        check("relaunch index of \(previewCount) entries", times, budget: .milliseconds(40))
        #expect(stores.count == times.count && stores.allSatisfy { $0.usedBytes == totalBytes })
        let last = try #require(stores.last)
        #expect(try previews.filter { try last.read($0.key) != $0.bytes }.isEmpty)
    }

    @Test(.enabled(if: optimized, "read timing needs an optimized build"))
    func readBudget() throws {
        let scratch = try PreviewScratch()
        let previews = try fill(scratch.folder, count: previewCount)
        let totalBytes = previewCount * payloadBytes
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: totalBytes)
        let clock = ContinuousClock()
        var mismatched = 0
        let times = try previews.map { p in
            var data: Data?
            let time = try clock.measure { data = try store.read(p.key) }
            if data != p.bytes { mismatched += 1 }
            return time
        }
        check("read one cached preview of \(previewCount)", times, budget: .microseconds(300))
        #expect(mismatched == 0)
    }
}
