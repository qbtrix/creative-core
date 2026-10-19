// ImageCodecShapeTests.swift: the image-codecs contract (IC-1). Each public
// symbol has the packet's signature, the side limits are 30,000, every stub
// throws `CodecError.unsupported` naming its task instead of trapping, the
// stored-block zlib writer lays out RFC 1950/1951 bytes, and the shared
// CRC-32 matches its published check value.
@testable import CoreRaster
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct ImageCodecShapeTests {
    @Test func signaturesMatchTheContract() {
        let functions: [Any] = [
            Inflate.zlib(_:limit:) as (Data, Int) throws -> Data, Inflate.raw(_:limit:) as (Data, Int) throws -> Data,
            Deflate.zlib(_:level:) as (Data, Int) -> Data,
            PNG.info as (Data) throws -> PNGInfo, PNG.read as (Data) throws -> PixelBuffer,
            PNG.write(_:bitsPerChannel:level:) as (PixelBuffer, Int, Int) throws -> Data,
            JPEG.info as (Data) throws -> JPEGInfo, JPEG.read as (Data) throws -> PixelBuffer,
            JPEG.write(_:quality:) as (PixelBuffer, Int) throws -> Data,
        ]
        #expect(functions.count == 9)
        let codec: any PixelCodec = PNGCodec(level: 9)
        #expect((codec as? PNGCodec)?.level == 9 && PNGCodec().level == 6)
        let png = PNGInfo(width: 2, height: 3, bitDepth: 16, colorType: 6, interlaced: true)
        #expect(png != PNGInfo(width: 2, height: 3, bitDepth: 8, colorType: 6, interlaced: true))
        let jpeg = JPEGInfo(width: 4, height: 5, components: 3, progressive: false, orientation: 6)
        #expect(jpeg.orientation == 6 && jpeg.components == 3 && !jpeg.progressive)
        #expect(PNG.maxSide == 30_000 && JPEG.maxSide == 30_000)
    }

    @Test func stubsThrowCodecErrors() throws {
        let buffer = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 0.5, g: 0.25, b: 0, a: 1))
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let stubs: [(String, () throws -> Any)] = [
            ("IC-4", { try PNG.info(bytes) }), ("IC-4", { try PNG.read(bytes) }),
            ("IC-5", { try PNG.write(buffer) }), ("IC-5", { try PNG.write(buffer, bitsPerChannel: 16, level: 0) }),
            ("IC-4", { try PNGCodec().decodePNG(bytes) }), ("IC-5", { try PNGCodec().encodePNG(buffer, bitsPerChannel: 8) }),
        ]
        for (task, stub) in stubs {
            do { _ = try stub(); Issue.record("\(task) stub returned") } catch CodecError.unsupported(let text) {
                #expect(text.hasSuffix("waits on \(task)"))
            } catch { Issue.record("expected CodecError.unsupported, got \(error)") }
        }
    }

    @Test func storedZlibBytes() {
        // Header 0x78 0x01, one final stored block (BFINAL 1, BTYPE 00), LEN 3
        // and NLEN, the bytes, then Adler-32("abc") = 0x024D0127.
        let abc = [UInt8](Deflate.zlib(Data("abc".utf8), level: 0))
        #expect(abc == [0x78, 0x01, 0x01, 0x03, 0x00, 0xFC, 0xFF, 0x61, 0x62, 0x63, 0x02, 0x4D, 0x01, 0x27])
        #expect([UInt8](Deflate.zlib(Data(), level: 0)) == [0x78, 0x01, 0x01, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01])
        #expect(Deflate.adler32(Array("Wikipedia".utf8)) == 0x11E6_0398)
        // 70,000 bytes: 65,535 in a block not final, then 4,465 in the final one.
        let input = [UInt8](repeating: 0xAB, count: 70_000)
        let stream = [UInt8](Deflate.zlib(Data(input), level: 0))
        #expect(stream.count == 2 + 5 + 65_535 + 5 + 4_465 + 4)
        #expect(Array(stream[2..<7]) == [0x00, 0xFF, 0xFF, 0x00, 0x00])
        #expect(Array(stream[65_542..<65_547]) == [0x01, 0x71, 0x11, 0x8E, 0xEE])
        #expect(Deflate.adler32(input) == stream.suffix(4).reduce(0) { $0 << 8 | UInt32($1) })
    }

    @Test func sharedCRC32() {
        #expect(ByteReader.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
        #expect(ByteReader.crc32(Array("IEND".utf8)) == 0xAE42_6082)
        #expect(ZipStore.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
    }
}
