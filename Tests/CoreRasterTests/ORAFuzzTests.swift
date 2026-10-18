// 1,000 seeded mutations of stack.xml throw a CodecError or open (LC-6).
import CoreRaster
import Foundation
import Testing

@Suite struct ORAFuzzTests {
    @Test func stackMutationsThrowOrOpen() throws {
        let stacks = mutations(of: [Data(ORAFixtures.stackA.utf8)], count: 1_000, seed: 0x0EA)
        fuzz(try stacks.map { try ORAFixtures.a(stack: String(decoding: $0, as: UTF8.self)) }) { _ = try OpenRaster.read($0, pixels: RawPixelCodec()) }
    }
}
