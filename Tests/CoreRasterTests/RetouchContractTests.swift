// RetouchContractTests.swift: retouch-heal RH-0, the contract slice's
// declarations. maxHealPixels and TonalRange are real; healed,
// filledFromSurroundings, dodge, burn, sponge and SmudgeState.dab are stubs
// that throw RasterError until RH-3 to RH-6 build them. Each of those tasks
// replaces its stub's check here with its own suite.
import CoreRaster
import Testing

@Test func maxHealPixelsIsFourMillion() {
    #expect(PixelBuffer.maxHealPixels == 4_000_000)
}

@Test func tonalRangeHasThreeCases() {
    let ranges: Set<TonalRange> = [.shadows, .midtones, .highlights]
    #expect(ranges.count == 3)
}

@Test func healStubsThrowRasterError() throws {
    let buffer = try PixelBuffer(width: 4, height: 4)
    let mask = try Mask(width: 4, height: 4, fill: 1)
    #expect(throws: RasterError.self) { try buffer.healed(offset: (dx: 1, dy: 0), through: mask) }
    #expect(throws: RasterError.self) { try buffer.filledFromSurroundings(mask, seed: 1) }
}

@Test func dabStubsThrowRasterError() throws {
    var buffer = try PixelBuffer(width: 4, height: 4)
    let dab = try Mask(width: 2, height: 2, fill: 1)
    #expect(throws: RasterError.self) { try buffer.dodge(dab, x: 0, y: 0, range: .midtones, exposure: 0.5) }
    #expect(throws: RasterError.self) { try buffer.burn(dab, x: 0, y: 0, range: .shadows, exposure: 0.5) }
    #expect(throws: RasterError.self) { try buffer.sponge(dab, x: 0, y: 0, amount: 0.5) }
}
