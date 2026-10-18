// ThumbnailStoreRecoveryTests.swift: the preview index's recovery and flush
// rate (PC-4). A damaged or newer index is set aside as `index.damaged.json`
// and rebuilt from the preview files, skipping files whose header is damaged;
// files gone from disk and orphan temp files are cleared at open; reads flush
// the index at most every 2 s and on close, merged with the index on disk; and
// a seeded fuzz of hostile indexes. The checks that read volumes through
// `entries(on:)` and `availability` wait on PC-5.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import CoreAsset
import Testing

private let card = VolumeRef(id: "vol-1", name: "Card A")
private let keys = ["IMG_0001", "IMG_0002", "IMG_0003"].map { previewKey($0) }

/// Fills a store in `folder` with `keys`, one 100-byte preview each, on `card`,
/// and closes it so its index is on disk.
private func fill(_ folder: URL) throws {
    let store = try ThumbnailStore(folder: folder, budgetBytes: 1 << 20)
    for (seed, key) in keys.enumerated() {
        try store.write(previewBytes(UInt8(seed)), for: key, volume: card, relativePath: "DCIM/\(key.asset).jpg")
    }
}

/// The index file's identity: a rewrite (in place or by rename) changes it.
private func stamp(_ url: URL) throws -> String {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let inode = attributes[.systemFileNumber].map { "\($0)" } ?? "-"
    let date = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return "\(inode)@\(date)"
}

@Suite struct ThumbnailStoreRecoveryTests {
    @Test func truncatedIndexIsRebuiltFromFiles() throws {
        let scratch = try PreviewScratch()
        try fill(scratch.folder)
        let index = try Data(contentsOf: scratch.index)
        try index.prefix(index.count / 2).write(to: scratch.index)

        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        for (seed, key) in keys.enumerated() {
            #expect(try store.read(key) == previewBytes(UInt8(seed)))
        }
        #expect(store.usedBytes == 300)
        #expect(try Data(contentsOf: scratch.damagedIndex) == index.prefix(index.count / 2))
        try store.remove(asset: keys[0].asset)
        #expect(try store.read(keys[0]) == nil)
        #expect(store.usedBytes == 200)
    }

    @Test(.disabled("waits on PC-5")) func rebuiltEntriesKeepTheirVolume() throws {
        let scratch = try PreviewScratch()
        try fill(scratch.folder)
        try Data("{".utf8).write(to: scratch.index)
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        // The volume and path come back from each file's header.
        #expect(store.entries(on: card).count == 3)
        #expect(store.availability(of: keys[0], mounted: []) == .offline(card))
        // A file gone from disk drops out of its volume's entries.
        try FileManager.default.removeItem(atPath: try #require(try scratch.previewFiles().first))
        #expect(try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20).entries(on: card).count == 2)
    }

    @Test func undecodableFilesAreSkippedAndKept() throws {
        let scratch = try PreviewScratch()
        try fill(scratch.folder)
        let junk = scratch.folder.appendingPathComponent("p/00/0000000000000000.bin")
        try FileManager.default.createDirectory(at: junk.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("FLPV not a header".utf8).write(to: junk)
        try Data("{\"version\":".utf8).write(to: scratch.index)

        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        for (seed, key) in keys.enumerated() {
            #expect(try store.read(key) == previewBytes(UInt8(seed)))
        }
        #expect(store.usedBytes == 300)
        #expect(FileManager.default.fileExists(atPath: junk.path))
    }

    @Test func orphanTempFilesAreRemovedAtOpen() throws {
        let scratch = try PreviewScratch()
        try fill(scratch.folder)
        let files = try scratch.previewFiles()
        let orphans = [files[0] + ".tmp", scratch.index.path + ".tmp"]
        for orphan in orphans { try Data("partial".utf8).write(to: URL(fileURLWithPath: orphan)) }

        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        for orphan in orphans { #expect(!FileManager.default.fileExists(atPath: orphan)) }
        #expect(try scratch.previewFiles() == files)
        #expect(try store.read(keys[0]) == previewBytes(0))
    }

    @Test func lastReadSurvivesRelaunch() throws {
        let scratch = try PreviewScratch()
        do {
            let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 300)
            for (seed, key) in keys.enumerated() {
                try store.write(previewBytes(UInt8(seed)), for: key, volume: nil, relativePath: nil)
            }
            #expect(try store.read(keys[0]) == previewBytes(0))
        }
        // The read reached the index on close, so the next write evicts keys[1].
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 300)
        try store.write(previewBytes(9), for: previewKey("IMG_0004"), volume: nil, relativePath: nil)
        #expect(try store.read(keys[1]) == nil)
        #expect(try store.read(keys[0]) == previewBytes(0))
    }

    @Test func flushMergesWithTheIndexOnDisk() throws {
        let scratch = try PreviewScratch()
        try fill(scratch.folder)
        let added = previewKey("IMG_0009")
        do {
            let reader = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
            let writer = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
            try writer.write(previewBytes(9), for: added, volume: nil, relativePath: nil)
            #expect(try reader.read(keys[0]) == previewBytes(0))
        }
        // The reader's close flushed its read without dropping the writer's entry.
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        #expect(try store.read(added) == previewBytes(9))
        #expect(store.usedBytes == 400)
    }

    @Test func fuzzedIndexThrowsOrRecovers() throws {
        let scratch = try PreviewScratch()
        try fill(scratch.folder)
        let valid = [UInt8](try Data(contentsOf: scratch.index))
        let tokens = ["-1", "999", "\(Int.max)", "null", "\"x\"", "[]", "{}", "1e400", ","].map { Array($0.utf8) }
        var rng = SplitMix64(state: 4_404)
        let start = ContinuousClock.now
        for round in 0..<1000 {
            var bytes = valid
            switch Int.random(in: 0..<3, using: &rng) {
            case 0: bytes = Array(bytes.prefix(Int.random(in: 0..<bytes.count, using: &rng)))
            case 1: for _ in 0..<Int.random(in: 1...4, using: &rng) { bytes[Int.random(in: 0..<bytes.count, using: &rng)] = .random(in: 0...255, using: &rng) }
            default:
                let at = Int.random(in: 0..<bytes.count, using: &rng)
                bytes.replaceSubrange(at..<min(bytes.count, at + Int.random(in: 0...6, using: &rng)), with: tokens[Int.random(in: 0..<tokens.count, using: &rng)])
            }
            // Every case through the codec, every tenth through a whole open.
            do throws(AssetError) { _ = try PreviewFiles.decodeIndex(Data(bytes)) } catch {
                #expect(error != .invalid(""))
            }
            guard round.isMultiple(of: 10) else { continue }
            try Data(bytes).write(to: scratch.index)
            do throws(AssetError) {
                let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
                for (seed, key) in keys.enumerated() {
                    let data = try store.read(key)
                    #expect(data == nil || data == previewBytes(UInt8(seed)))
                }
            } catch {
                #expect(error != .invalid(""))  // a typed error that names its cause
            }
        }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func newerSetAside() throws {
        let scratch = try PreviewScratch()
        try fill(scratch.folder)
        // Rewrite the index's version number to one this build doesn't know.
        let bytes = [UInt8](try Data(contentsOf: scratch.index))
        let field = Array("\"version\"".utf8)
        let isDigit: (UInt8) -> Bool = { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
        let at = try #require(bytes.indices.first { Array(bytes[$0...].prefix(field.count)) == field })
        let digits = try #require(bytes[(at + field.count)...].firstIndex(where: isDigit))
        let end = bytes[digits...].firstIndex(where: { !isDigit($0) }) ?? bytes.endIndex
        let newer = Data(bytes[..<digits] + Array("999".utf8) + bytes[end...])
        try newer.write(to: scratch.index)

        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        #expect(try Data(contentsOf: scratch.damagedIndex) == newer)
        for (seed, key) in keys.enumerated() {
            #expect(try store.read(key) == previewBytes(UInt8(seed)))
        }
    }

    @Test func missingFilesDropOut() throws {
        let scratch = try PreviewScratch()
        try fill(scratch.folder)
        let files = try scratch.previewFiles()
        #expect(files.count == 3)
        try FileManager.default.removeItem(atPath: try #require(files.first))

        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        #expect(store.usedBytes == 200)  // dropped at open, before a read finds it gone
        var found = 0
        for (seed, key) in keys.enumerated() {
            let data = try store.read(key)
            if data != nil { found += 1 }
            #expect(data == nil || data == previewBytes(UInt8(seed)))
        }
        #expect(found == 2)
        #expect(store.usedBytes == 200)
    }

    @Test func scrollFlushesRarely() throws {
        let scratch = try PreviewScratch()
        try fill(scratch.folder)
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        var last = try stamp(scratch.index)
        var flushes = 0
        for n in 0..<1000 {
            _ = try store.read(keys[n % keys.count])
            let now = try stamp(scratch.index)
            if now != last { flushes += 1 }
            last = now
        }
        #expect(flushes <= 2)
    }
}
