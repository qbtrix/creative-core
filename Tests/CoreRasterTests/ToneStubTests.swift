// ToneStubTests.swift: the tone-pack contract stub (TP-0) as it stands
// before TP-6 fills it. `AutoTone.suggest` throws
// `RasterError.invalid("not built")` and `AutoTone` holds the five values it
// is given. TP-6 deletes the rows here that its op outgrows.
import CoreRaster
import Testing

private let notBuilt = RasterError.invalid("not built")

private func sample() throws -> PixelBuffer {
    try PixelBuffer(width: 2, height: 2, fill: RGBA(r: 0.2, g: 0.4, b: 0.6, a: 1))
}

@Test func autoToneStubThrowsNotBuilt() throws {
    #expect(throws: notBuilt) { try AutoTone.suggest(for: try sample()) }
}

@Test func autoToneHoldsItsValues() {
    let tone = AutoTone(inBlack: 0.1, inWhite: 0.9, gamma: 1.2, temperature: -5, tint: 3)
    #expect(tone.inBlack == 0.1)
    #expect(tone.inWhite == 0.9)
    #expect(tone.gamma == 1.2)
    #expect(tone.temperature == -5)
    #expect(tone.tint == 3)
    #expect(tone != AutoTone(inBlack: 0, inWhite: 1, gamma: 1, temperature: 0, tint: 0))
}
