// ToneStubTests.swift: the tone-pack contract stubs (TP-0) as they stand
// before TP-3..TP-6 fill them. Every throwing op throws
// `RasterError.invalid("not built")`, `inverted()` returns its input, and
// `AutoTone` holds the five values it is given. Each filling task deletes the
// rows here that its op outgrows.
import CoreRaster
import Testing

private let notBuilt = RasterError.invalid("not built")

private func sample() throws -> PixelBuffer {
    try PixelBuffer(width: 2, height: 2, fill: RGBA(r: 0.2, g: 0.4, b: 0.6, a: 1))
}

@Test func mixStubsThrowNotBuilt() throws {
    let buffer = try sample()
    let identity = ChannelMatrix(red: [1, 0, 0, 0], green: [0, 1, 0, 0], blue: [0, 0, 1, 0], monochrome: false)
    let balance = ToneBalance(shadows: .zero, midtones: .zero, highlights: .zero, preserveLuminosity: true)
    #expect(throws: notBuilt) { try buffer.blackAndWhite(GrayMix()) }
    #expect(throws: notBuilt) { try buffer.channelMixer(identity) }
    #expect(throws: notBuilt) { try buffer.colorBalance(balance) }
}

@Test func mapStubsThrowNotBuilt() throws {
    let buffer = try sample()
    let stops = [GradientMapStop(offset: 0, color: RGBA(r: 0, g: 0, b: 0, a: 1)),
                 GradientMapStop(offset: 1, color: RGBA(r: 1, g: 1, b: 1, a: 1))]
    let lut = try ColorLUT(size: 2, table: Array(repeating: SIMD3<Float>(0.5, 0.5, 0.5), count: 8))
    #expect(throws: notBuilt) { try buffer.gradientMap(stops) }
    #expect(throws: notBuilt) { try buffer.applying(lut) }
    #expect(throws: notBuilt) { try buffer.posterized(levels: 4) }
    #expect(throws: notBuilt) { try buffer.thresholded(0.5) }
    #expect(throws: notBuilt) { try CubeLUT.parse("LUT_3D_SIZE 2\n") }
    #expect(throws: notBuilt) { try AutoTone.suggest(for: buffer) }
}

@Test func invertedStubReturnsInput() throws {
    let buffer = try sample()
    #expect(buffer.inverted() == buffer)
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
