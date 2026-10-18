// ThumbnailStoreRecoveryTests.swift: the preview index's recovery and flush
// rate (PC-4). A damaged or newer index is set aside as `index.damaged.json`
// and rebuilt from the preview files; files gone from disk drop out; reads
// flush the index at most every 2 s. Written first from the packet and
// disabled until PC-4 builds the index codec.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreAsset
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
    @Test(.disabled("waits on PC-4")) func truncatedIndexIsRebuiltFromFiles() throws {
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
    }

    @Test(.disabled("waits on PC-4")) func newerSetAside() throws {
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

    @Test(.disabled("waits on PC-4")) func missingFilesDropOut() throws {
        let scratch = try PreviewScratch()
        try fill(scratch.folder)
        let files = try scratch.previewFiles()
        #expect(files.count == 3)
        try FileManager.default.removeItem(atPath: try #require(files.first))

        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        var found = 0
        for (seed, key) in keys.enumerated() {
            let data = try store.read(key)
            if data != nil { found += 1 }
            #expect(data == nil || data == previewBytes(UInt8(seed)))
        }
        #expect(found == 2)
        #expect(store.usedBytes == 200)
        #expect(store.entries(on: card).count == 2)
    }

    @Test(.disabled("waits on PC-4")) func scrollFlushesRarely() throws {
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
