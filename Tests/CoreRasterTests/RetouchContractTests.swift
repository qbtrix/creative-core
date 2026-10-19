// RetouchContractTests.swift: retouch-heal's contract constants, maxHealPixels
// and TonalRange; each retouch op is checked in its own suite.
import CoreRaster
import Testing

@Test func maxHealPixelsIsFourMillion() {
    #expect(PixelBuffer.maxHealPixels == 4_000_000)
}

@Test func tonalRangeHasThreeCases() {
    let ranges: Set<TonalRange> = [.shadows, .midtones, .highlights]
    #expect(ranges.count == 3)
}
