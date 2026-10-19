import CoreRender
import Testing
@Test func tmpCountSamples() throws {
    let n = try ParityPack.all.map { try $0.bands().count }
    print("TMPCOUNT packs=\(n.count) samples=\(n.reduce(0, +)) \(n)")
}
