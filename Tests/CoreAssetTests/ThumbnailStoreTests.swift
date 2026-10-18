// ThumbnailStoreTests.swift: the preview store's write, read, relaunch, budget,
// remove, atomic replace and lock (PC-3). Written first from the packet's
// acceptance tests and disabled until PC-3 builds the store. Also holds the
// scratch-folder helpers the recovery and offline suites share.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreAsset
import Testing

/// A fresh, empty folder for one test's store, removed when the test ends.
struct PreviewScratch: ~Copyable {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("previews-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    var index: URL { folder.appendingPathComponent("index.json") }
    var damagedIndex: URL { folder.appendingPathComponent("index.damaged.json") }

    /// The preview files on disk (`p/<2 hex>/<digest>.bin`), sorted, as full paths.
    func previewFiles() throws -> [String] {
        let root = folder.appendingPathComponent("p").path
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        return try FileManager.default.subpathsOfDirectory(atPath: root)
            .filter { $0.hasSuffix(".bin") }
            .sorted()
            .map { root + "/" + $0 }
    }
}

/// `count` bytes that differ for each `seed`, so a mixed-up preview shows.
func previewBytes(_ seed: UInt8, count: Int = 100) -> Data {
    Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
}

func previewKey(_ asset: String, _ size: SizeClass = .medium) -> PreviewKey {
    PreviewKey(asset: asset, content: "sha-\(asset)", size: size)
}

@Suite struct ThumbnailStoreTests {
    @Test(.disabled("waits on PC-3")) func writeThenReadIsEqual() throws {
        let scratch = try PreviewScratch()
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        let key = previewKey("IMG_0001")
        try store.write(previewBytes(1), for: key, volume: nil, relativePath: nil)
        #expect(try store.read(key) == previewBytes(1))
        #expect(store.usedBytes == 100)
        #expect(try store.read(previewKey("IMG_0002")) == nil)
        #expect(try store.read(PreviewKey(asset: "IMG_0001", content: "sha-other", size: .medium)) == nil)
    }

    @Test(.disabled("waits on PC-3")) func writeReplacesEarlierPreview() throws {
        let scratch = try PreviewScratch()
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        let key = previewKey("IMG_0001")
        try store.write(previewBytes(1), for: key, volume: nil, relativePath: nil)
        try store.write(previewBytes(2, count: 40), for: key, volume: nil, relativePath: nil)
        #expect(try store.read(key) == previewBytes(2, count: 40))
        #expect(store.usedBytes == 40)
    }

    @Test(.disabled("waits on PC-3")) func secondStoreReadsAfterRelaunch() throws {
        let scratch = try PreviewScratch()
        let keys = SizeClass.allCases.map { previewKey("IMG_0001", $0) } + [previewKey("IMG_0002")]
        do {
            let first = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
            for (seed, key) in keys.enumerated() {
                try first.write(previewBytes(UInt8(seed)), for: key, volume: nil, relativePath: nil)
            }
        }
        let second = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        for (seed, key) in keys.enumerated() {
            #expect(try second.read(key) == previewBytes(UInt8(seed)))
        }
        #expect(second.usedBytes == 400)
    }

    @Test(.disabled("waits on PC-3")) func evictsLeastRecentlyRead() throws {
        let scratch = try PreviewScratch()
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 300)
        let keys = ["a", "b", "c", "d"].map { previewKey($0) }
        for (seed, key) in keys.enumerated() {
            try store.write(previewBytes(UInt8(seed)), for: key, volume: nil, relativePath: nil)
        }
        #expect(store.usedBytes == 300)
        #expect(try store.read(keys[0]) == nil)
        for (seed, key) in keys.enumerated().dropFirst() {
            #expect(try store.read(key) == previewBytes(UInt8(seed)))
        }
    }

    @Test(.disabled("waits on PC-3")) func readBumpsRecency() throws {
        let scratch = try PreviewScratch()
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 300)
        let keys = ["a", "b", "c", "d"].map { previewKey($0) }
        for (seed, key) in keys.prefix(3).enumerated() {
            try store.write(previewBytes(UInt8(seed)), for: key, volume: nil, relativePath: nil)
        }
        #expect(try store.read(keys[0]) == previewBytes(0))
        try store.write(previewBytes(3), for: keys[3], volume: nil, relativePath: nil)
        #expect(store.usedBytes == 300)
        #expect(try store.read(keys[1]) == nil)
        #expect(try store.read(keys[0]) == previewBytes(0))
        #expect(try store.read(keys[2]) == previewBytes(2))
        #expect(try store.read(keys[3]) == previewBytes(3))
    }

    @Test(.disabled("waits on PC-3")) func removeDropsEverySizeClass() throws {
        let scratch = try PreviewScratch()
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        for size in SizeClass.allCases {
            try store.write(previewBytes(1), for: previewKey("gone", size), volume: nil, relativePath: nil)
        }
        try store.write(previewBytes(2), for: previewKey("kept"), volume: nil, relativePath: nil)
        try store.remove(asset: "gone")
        for size in SizeClass.allCases {
            #expect(try store.read(previewKey("gone", size)) == nil)
        }
        #expect(try store.read(previewKey("kept")) == previewBytes(2))
        #expect(store.usedBytes == 100)
        #expect(try scratch.previewFiles().count == 1)
    }

    @Test(.disabled("waits on PC-3")) func interruptedWriteKeepsOld() async throws {
        let scratch = try PreviewScratch()
        let key = previewKey("IMG_0001")
        let old = Data(repeating: 0x11, count: 1 << 16)
        let new = Data(repeating: 0x22, count: 1 << 16)
        let writer = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 24)
        try writer.write(old, for: key, volume: nil, relativePath: nil)

        // A crash before the rename leaves only a partial temp file beside the
        // preview: a relaunched store still reads the old bytes whole.
        let file = try #require(try scratch.previewFiles().first)
        try new.prefix(1000).write(to: URL(fileURLWithPath: file + ".tmp"))
        let relaunched = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 24)
        #expect(try relaunched.read(key) == old)
        #expect(relaunched.usedBytes == old.count)

        // While one store rewrites the preview, another only ever sees a
        // complete old or new preview, never a part-written one.
        let reader = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 24)
        let torn = try await withThrowingTaskGroup(of: Int.self) { group in
            group.addTask {
                for round in 0..<200 {
                    try writer.write(round.isMultiple(of: 2) ? new : old, for: key, volume: nil, relativePath: nil)
                }
                return 0
            }
            group.addTask {
                var torn = 0
                for _ in 0..<2000 {
                    let seen = try reader.read(key)
                    if seen != old && seen != new { torn += 1 }
                }
                return torn
            }
            return try await group.reduce(0, +)
        }
        #expect(torn == 0)
    }

    @Test(.disabled("waits on PC-3")) func twoStoresUnderTheLockLoseNothing() async throws {
        let scratch = try PreviewScratch()
        let left = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 24)
        let right = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 24)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (side, store) in [("L", left), ("R", right)] {
                group.addTask {
                    for n in 0..<50 {
                        try store.write(previewBytes(UInt8(n)), for: previewKey("\(side)\(n)"), volume: nil, relativePath: nil)
                    }
                }
            }
            try await group.waitForAll()
        }
        let reopened = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 24)
        for side in ["L", "R"] {
            for n in 0..<50 {
                #expect(try reopened.read(previewKey("\(side)\(n)")) == previewBytes(UInt8(n)))
            }
        }
        #expect(reopened.usedBytes == 100 * 100)
        #expect(try scratch.previewFiles().count == 100)
    }
}
