// PreviewJournalTests.swift: filling a store writes index bytes linear in the
// previews (counted, not timed) and compacts the journal; a version 1 index
// still loads; an unfinished last line is ignored and cut, a damaged line
// rebuilds from the files; a store sees another store's compaction.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import CoreAsset
import Testing

private func journal(_ scratch: borrowing PreviewScratch) -> URL {
    scratch.folder.appendingPathComponent("index.journal")
}

@Suite struct PreviewJournalTests {
    @Test func fillingWritesLinearIndexBytes() throws {
        let scratch = try PreviewScratch()
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 30)
        let count = 1_000
        for n in 0..<count {
            try store.write(previewBytes(UInt8(n & 0xFF)), for: previewKey("IMG_\(n)"), volume: nil, relativePath: "DCIM/IMG_\(n).jpg")
        }
        let ledger = store.currentLedger
        #expect(ledger.bytesWritten + ledger.bytesRead < 1_024 * count)  // a rewrite per write: ~100 MB
        #expect(ledger.indexWrites < count + 40)
        #expect(ledger.journalRecords <= count / 2 + 1)
        #expect(try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 30).usedBytes == 100 * count)
    }

    @Test func versionOneIndexStillLoads() throws {
        let scratch = try PreviewScratch()
        let keys = ["IMG_0001", "IMG_0002"].map { previewKey($0) }
        do {
            let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
            for (seed, key) in keys.enumerated() { try store.write(previewBytes(UInt8(seed)), for: key, volume: nil, relativePath: nil) }
        }
        // The index as PC-4 wrote it: version 1, no generation, no journal.
        try FileManager.default.removeItem(at: journal(scratch))
        let entries = keys.enumerated().map { seed, key in
            "{\"key\":{\"asset\":\"\(key.asset)\",\"content\":\"\(key.content)\",\"size\":1024},\"byteCount\":100,\"lastRead\":\(seed + 5)}"
        }
        try Data("{\"version\":1,\"budgetBytes\":1048576,\"entries\":[\(entries.joined(separator: ","))]}".utf8).write(to: scratch.index)

        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        #expect(store.currentEntries[keys[1]]?.lastRead == Date(timeIntervalSinceReferenceDate: 6))  // from the index, not rebuilt
        #expect(!FileManager.default.fileExists(atPath: scratch.damagedIndex.path))
        for (seed, key) in keys.enumerated() { #expect(try store.read(key) == previewBytes(UInt8(seed))) }
        #expect(try PreviewFiles.decodeIndex(Data(contentsOf: scratch.index)).generation != nil)  // upgraded at open
    }

    @Test func unfinishedLastLineIsIgnoredAndCut() throws {
        let scratch = try PreviewScratch()
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        try store.write(previewBytes(1), for: previewKey("a"), volume: nil, relativePath: nil)
        try (Data(contentsOf: journal(scratch)) + Data("{\"put\":{\"key\"".utf8)).write(to: journal(scratch))  // a crash mid-append

        let relaunched = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        #expect(try relaunched.read(previewKey("a")) == previewBytes(1))
        try relaunched.write(previewBytes(2), for: previewKey("b"), volume: nil, relativePath: nil)
        #expect(try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20).usedBytes == 200)
        #expect(!FileManager.default.fileExists(atPath: scratch.damagedIndex.path))
    }

    @Test func damagedLineRebuildsFromFiles() throws {
        let scratch = try PreviewScratch()
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        for (seed, name) in ["a", "b"].enumerated() { try store.write(previewBytes(UInt8(seed)), for: previewKey(name), volume: nil, relativePath: nil) }
        let bytes = try Data(contentsOf: journal(scratch))
        try (bytes.prefix(23) + Data("{\"put\":7}\n".utf8) + bytes.dropFirst(23)).write(to: journal(scratch))

        let relaunched = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        #expect(FileManager.default.fileExists(atPath: scratch.folder.appendingPathComponent("index.damaged.journal").path))
        #expect(try relaunched.read(previewKey("a")) == previewBytes(0))
        #expect(try relaunched.read(previewKey("b")) == previewBytes(1))
    }

    @Test func anotherStoresCompactionIsSeen() throws {
        let scratch = try PreviewScratch()
        let left = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        let right = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        for n in 0..<100 { try left.write(previewBytes(UInt8(n)), for: previewKey("L\(n)"), volume: nil, relativePath: nil) }
        #expect(left.currentLedger.generation != right.currentLedger.generation)  // left compacted past 64 records
        try right.write(previewBytes(7), for: previewKey("R"), volume: nil, relativePath: nil)
        #expect(right.usedBytes == 101 * 100)
        try left.remove(asset: "R")
        #expect(left.usedBytes == 100 * 100)
        #expect(try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20).usedBytes == 100 * 100)
    }
}
