// OfflineVolumeTests.swift: previews of originals on removable volumes (PC-5).
// An entry whose volume isn't mounted still reads its bytes and reports
// `.offline(volume)`; `entries(on:)` lists one volume's entries; an entry with
// no volume is always online; volumes match by id, so a renamed one still
// lists its entries.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreAsset
import Testing

private let cardA = VolumeRef(id: "vol-a", name: "Card A")
private let cardB = VolumeRef(id: "vol-b", name: "Card B")

@Suite struct OfflineVolumeTests {
    @Test func unmountedIsOffline() throws {
        let scratch = try PreviewScratch()
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        let key = previewKey("IMG_0001")
        try store.write(previewBytes(1), for: key, volume: cardA, relativePath: "DCIM/IMG_0001.jpg")
        #expect(store.availability(of: key, mounted: []) == .offline(cardA))
        #expect(store.availability(of: key, mounted: ["vol-b"]) == .offline(cardA))
        #expect(store.availability(of: key, mounted: ["vol-a", "vol-b"]) == .online)
        #expect(try store.read(key) == previewBytes(1))
        #expect(store.availability(of: previewKey("absent"), mounted: []) == nil)
    }

    @Test func noVolumeIsOnline() throws {
        let scratch = try PreviewScratch()
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        let key = previewKey("loose")
        try store.write(previewBytes(2), for: key, volume: nil, relativePath: nil)
        #expect(store.availability(of: key, mounted: []) == .online)
        #expect(store.availability(of: key, mounted: ["vol-a"]) == .online)
    }

    @Test func entriesListOnlyThatVolume() throws {
        let scratch = try PreviewScratch()
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        try store.write(previewBytes(1), for: previewKey("a1"), volume: cardA, relativePath: "DCIM/a1.jpg")
        try store.write(previewBytes(2, count: 50), for: previewKey("a2", .small), volume: cardA, relativePath: "DCIM/a2.jpg")
        try store.write(previewBytes(3), for: previewKey("b1"), volume: cardB, relativePath: "b1.jpg")
        try store.write(previewBytes(4), for: previewKey("loose"), volume: nil, relativePath: nil)

        let onA = store.entries(on: cardA).sorted { $0.key.asset < $1.key.asset }
        #expect(onA.map(\.key) == [previewKey("a1"), previewKey("a2", .small)])
        #expect(onA.map(\.byteCount) == [100, 50])
        #expect(onA.map(\.relativePath) == ["DCIM/a1.jpg", "DCIM/a2.jpg"])
        #expect(onA.allSatisfy { $0.volume == cardA })
        #expect(store.entries(on: cardB).map(\.key) == [previewKey("b1")])
        #expect(store.entries(on: VolumeRef(id: "vol-c", name: "Card C")).isEmpty)
    }

    @Test func renamedVolumeMatchesById() throws {
        let scratch = try PreviewScratch()
        let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        try store.write(previewBytes(1), for: previewKey("a1"), volume: cardA, relativePath: "DCIM/a1.jpg")
        try store.write(previewBytes(2), for: previewKey("b1"), volume: VolumeRef(id: "vol-b", name: "Card A"), relativePath: "b1.jpg")
        let renamed = VolumeRef(id: "vol-a", name: "Holiday Card")
        #expect(store.entries(on: renamed).map(\.key) == [previewKey("a1")])
        #expect(store.entries(on: renamed).map(\.volume) == [cardA])
        #expect(store.availability(of: previewKey("a1"), mounted: [renamed.id]) == .online)
    }

    @Test func offlineEntriesSurviveRelaunch() throws {
        let scratch = try PreviewScratch()
        let key = previewKey("IMG_0001")
        do {
            let store = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
            try store.write(previewBytes(1), for: key, volume: cardA, relativePath: "DCIM/IMG_0001.jpg")
        }
        let reopened = try ThumbnailStore(folder: scratch.folder, budgetBytes: 1 << 20)
        #expect(reopened.availability(of: key, mounted: []) == .offline(cardA))
        #expect(reopened.entries(on: cardA).map(\.relativePath) == ["DCIM/IMG_0001.jpg"])
        #expect(try reopened.read(key) == previewBytes(1))
    }
}
