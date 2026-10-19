// ToneStubTests.swift: what is left of the tone-pack contract stub (TP-0)
// once TP-6 filled `AutoTone.suggest` (its checks are `AutoToneTests`):
// `AutoTone` holds the five values it is given.
import CoreRaster
import Testing

@Test func autoToneHoldsItsValues() {
    let tone = AutoTone(inBlack: 0.1, inWhite: 0.9, gamma: 1.2, temperature: -5, tint: 3)
    #expect(tone.inBlack == 0.1)
    #expect(tone.inWhite == 0.9)
    #expect(tone.gamma == 1.2)
    #expect(tone.temperature == -5)
    #expect(tone.tint == 3)
    #expect(tone != AutoTone(inBlack: 0, inWhite: 1, gamma: 1, temperature: 0, tint: 0))
}
