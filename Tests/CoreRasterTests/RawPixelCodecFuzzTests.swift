// RawPixelCodecFuzzTests.swift: seeded fuzzing of RawPixelCodec.decodePNG.
// Random byte flips, truncations and appends of a valid encoding either throw
// `CodecError` or decode to a buffer whose size matches the byte count; none
// crash.
import CoreRaster
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct RawPixelCodecFuzzTests {
    @Test func randomByteFlipsThrowOrDecodeToTheRightSize() throws {
        var rng = SplitMix64(seed: 0x5241_5750)
        let codec = RawPixelCodec()
        var buffer = try PixelBuffer(width: 3, height: 2, fill: .clear)
        for y in 0..<2 { for x in 0..<3 { try buffer.setPixel(x: x, y: y, randomPixel(&rng)) } }
        let good = [UInt8](try codec.encodePNG(buffer, bitsPerChannel: 16))
        #expect(try codec.decodePNG(Data(good)) == buffer)
        var decoded = 0
        for _ in 0..<2_000 {
            var bytes = good
            for _ in 0..<Int.random(in: 1...4, using: &rng) {
                let at = Int.random(in: 0..<bytes.count, using: &rng)
                bytes[at] = UInt8.random(in: 0...255, using: &rng)
            }
            switch Int.random(in: 0..<4, using: &rng) {
            case 0: bytes.removeLast(Int.random(in: 1...bytes.count, using: &rng))
            case 1: bytes += (0..<Int.random(in: 1...8, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
            default: break
            }
            do {
                let image = try codec.decodePNG(Data(bytes))
                // A 13-byte header, then four 4-byte components per pixel.
                #expect(13 + image.width * image.height * 16 == bytes.count)
                for y in 0..<image.height { for x in 0..<image.width { #expect(try image.pixel(x: x, y: y).isFinite) } }
                decoded += 1
            } catch is CodecError {
                continue
            }
        }
        // Flips inside the components alone still decode, so both paths run.
        #expect(decoded > 0)
    }
}
