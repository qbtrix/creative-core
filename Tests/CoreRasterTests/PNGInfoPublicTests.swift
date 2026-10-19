// PNGInfoPublicTests.swift: `PNGInfo` seen as a caller outside CoreRaster
// sees it, through a plain import (no @testable, which is per file): its
// public initializer builds an expected value to compare `PNG.info` against.
import CoreRaster
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct PNGInfoPublicTests {
    @Test func publicInitBuildsExpectedValue() throws {
        let made = PNGInfo(width: 1, height: 1, bitDepth: 8, colorType: 6, interlaced: false)
        #expect(made.width == 1 && made.height == 1 && made.bitDepth == 8 && made.colorType == 6 && !made.interlaced)
        let pixels = try PixelBuffer(width: 1, height: 1)
        #expect(try PNG.info(PNG.write(pixels, bitsPerChannel: 8, level: 6)) == made)
    }
}
