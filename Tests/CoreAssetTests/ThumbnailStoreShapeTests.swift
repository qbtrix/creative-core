// ThumbnailStoreShapeTests.swift: the preview store's public shape (PC-1).
// The value types round-trip through JSON, the size classes keep their pixel
// edges, and every store member exists: the throwing ones throw `AssetError`
// until PC-3 builds them, the others answer empty.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreAsset
import Testing

private let card = VolumeRef(id: "vol-1", name: "Card A")
private let key = PreviewKey(asset: "IMG_0001", content: "sha-abc", size: .medium)

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

@Suite struct ThumbnailStoreShapeTests {
    @Test func sizeClassesKeepTheirEdges() {
        #expect(SizeClass.allCases.map(\.rawValue) == [256, 1024, 2560])
    }

    @Test func valuesAreCodable() throws {
        #expect(try roundTrip(card) == card)
        #expect(try roundTrip(SizeClass.large) == .large)
        #expect(try roundTrip(key) == key)
        let entry = PreviewEntry(key: key, byteCount: 4096, volume: card,
                                 relativePath: "DCIM/IMG_0001.jpg",
                                 lastRead: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try roundTrip(entry) == entry)
        let loose = PreviewEntry(key: key, byteCount: 1, volume: nil, relativePath: nil,
                                 lastRead: Date(timeIntervalSince1970: 0))
        #expect(try roundTrip(loose) == loose)
    }

    @Test func availabilityNamesTheVolume() {
        #expect(Availability.offline(card) != .online)
        #expect(Availability.offline(card) == .offline(VolumeRef(id: "vol-1", name: "Card A")))
    }

    @Test func storeStubsThrowAssetError() throws {
        let folder = URL(fileURLWithPath: "/nonexistent/previews", isDirectory: true)
        let store = try ThumbnailStore(folder: folder, budgetBytes: 1 << 20)
        let notBuilt = AssetError.invalid("not built")
        #expect(throws: notBuilt) {
            try store.write(Data([1, 2, 3]), for: key, volume: card, relativePath: "a.jpg")
        }
        #expect(throws: notBuilt) { _ = try store.read(key) }
        #expect(throws: notBuilt) { try store.remove(asset: "IMG_0001") }
        #expect(store.entries(on: card).isEmpty)
        #expect(store.availability(of: key, mounted: ["vol-1"]) == nil)
        #expect(store.usedBytes == 0)
    }
}
