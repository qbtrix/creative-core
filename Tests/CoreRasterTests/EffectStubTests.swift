// EffectStubTests.swift: the effects-engine contract stubs (FX-0) compile
// with the packet's signatures and throw "not built" until FX-3..FX-7 fill
// them. Each filling task replaces the matching case here with real checks.
import CoreRaster
import Testing

@Suite struct EffectStubTests {
    let notBuilt = RasterError.invalid("not built")
    let red = RGBA(r: 1, g: 0, b: 0, a: 1)

    @Test func applyingThrowsNotBuiltForEveryCase() throws {
        let buffer = try PixelBuffer(width: 4, height: 4, fill: red)
        let effects: [LayerEffect] = [
            .boxBlur(radius: 1), .motionBlur(degrees: 45, distance: 2), .denoise(strength: 1, detail: 0),
            .clarity(amount: 50, radius: 10), .glow(color: red, radius: 2, intensity: 1, inner: true),
            .shadow(color: red, dx: 1, dy: 1, blur: 1, inner: false), .stroke(color: red, width: 1, position: .center),
        ]
        for effect in effects {
            #expect(throws: notBuilt) { try buffer.applying(effect) }
        }
    }
}
