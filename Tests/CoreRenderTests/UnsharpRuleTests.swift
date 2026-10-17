// UnsharpRuleTests.swift: the Metal unsharp kernel's rule (MB-12) is Float32 arithmetic (Float(threshold), a strict
// compare, a fused multiply-add), as UnsharpShader's `sharpen`; it agrees with CoreRaster's Double `unsharpMask`
// to Float rounding, a difference that close to the threshold taking either branch; invalid parameters and a
// non-finite result throw the CPU backend's exact errors.
import CoreRaster
import CoreRender
import Testing

@Suite struct UnsharpRuleTests {
    /// Each component of a one-pixel-high buffer through the rule, against CoreRaster's blur of the buffer, is
    /// CoreRaster's unsharp mask of it to Float rounding; a component whose Double difference is within 1e-6 of
    /// the threshold may instead take the other branch.
    @Test func matchesCoreRasterOnALine() throws {
        var rng = ParityRandom(seed: 0x5A4B)
        for (amount, threshold) in [(1.0, 0.0), (0.0, 0.0), (2.5, 0.05), (-0.5, 0.02), (1.5, 0.2), (3, 1)] {
            for (length, sigma) in [(1, 0.0), (9, 1.0), (61, 2.5)] {
                var buffer = try PixelBuffer(width: length, height: 1)
                for x in 0..<length {
                    let a = Float.random(in: 0...1, using: &rng)
                    try buffer.setPixel(x: x, y: 0, RGBA(r: Float.random(in: 0...a, using: &rng), g: a / 3, b: 0, a: a))
                }
                let want = try buffer.unsharpMask(amount: amount, sigma: sigma, threshold: threshold)
                let blurred = try buffer.gaussianBlur(sigma: sigma)
                let rule = try UnsharpRule(amount: amount, threshold: threshold)
                for x in 0..<length {
                    let (p, b, w) = (try buffer.pixel(x: x, y: 0), try blurred.pixel(x: x, y: 0), try want.pixel(x: x, y: 0))
                    for (c, blur, want) in [(p.r, b.r, w.r), (p.g, b.g, w.g), (p.b, b.b, w.b), (p.a, b.a, w.a)] {
                        let got = rule.apply(c, blurred: blur)
                        let difference = Double(c) - Double(blur)
                        let close = { (u: Float, v: Float) in abs(u - v) <= 1e-6 }
                        let tie = abs(abs(difference) - threshold) <= 1e-6
                        let other = abs(difference) > threshold ? c : Float(Double(c) + amount * difference)
                        #expect(close(got, want) || (tie && close(got, other)),
                                "amount \(amount) threshold \(threshold) sigma \(sigma) pixel \(x)")
                    }
                }
            }
        }
    }

    /// The rule compares the Float difference with Float(threshold), as the kernel does, not the Double
    /// difference with the Double threshold as CoreRaster does: a threshold just under a difference rounds up
    /// to it in Float, so the kernel and the rule leave the component alone where CoreRaster sharpens it.
    @Test func comparesInFloatAsTheKernelDoes() throws {
        let (x, blurred): (Float, Float) = (0.6, 0.5)
        let difference = x - blurred
        let threshold = Double(difference) - 1e-10
        #expect(Float(threshold) == difference && Double(difference) > threshold)
        let rule = try UnsharpRule(amount: 1, threshold: threshold)
        #expect(rule.apply(x, blurred: blurred) == x, "at Float(threshold): unchanged, as the kernel")
        let over = try UnsharpRule(amount: 1, threshold: Double(difference) - 1e-8)
        #expect(Float(over.threshold) < difference)
        #expect(over.apply(x, blurred: blurred) == x + difference, "over Float(threshold): sharpened")
    }

    /// The kernel's `sharpen` is fma(amount, d, x): one rounding, which `apply` matches. With x = -1 and amount =
    /// d = 1 + 2^-12, the exact result 2^-11 + 2^-24 is a Float, while x + amount * d rounds the product first and
    /// gives 2^-11.
    @Test func sharpensWithOneFusedRounding() throws {
        let step = Float(1).addingProduct(1, 0x1p-12)
        let rule = try UnsharpRule(amount: Double(step), threshold: 0)
        let x: Float = -1, blurred = x - step
        #expect(x - blurred == step)
        #expect(rule.apply(x, blurred: blurred) == 0x1p-11 + 0x1p-24)
        #expect(x + step * step == 0x1p-11, "unfused rounds the product first")
    }

    /// A difference exactly at the threshold is left alone; one just over it is sharpened.
    @Test func theThresholdIsStrict() throws {
        let rule = try UnsharpRule(amount: 2, threshold: 0.25)
        #expect(rule.apply(0.75, blurred: 0.5) == 0.75, "at the threshold: unchanged")
        #expect(rule.apply(0.5, blurred: 0.75) == 0.5)
        #expect(rule.apply(0.875, blurred: 0.5) == 1.625, "over it: 0.875 + 2 x 0.375")
        #expect(rule.apply(0.5, blurred: 0.875) == -0.25)
        #expect(rule.parameters == [2, 0.25])
    }

    /// Every amount or threshold CoreRaster rejects throws the same `RenderError` from the rule as from the CPU
    /// backend; an amount that overflows a component throws the CPU's overflow error from `check`.
    @Test func invalidParametersThrowTheCPUBackendsError() throws {
        let cpu = CPUBackend()
        var buffer = try PixelBuffer(width: 4, height: 1)
        try buffer.setPixel(x: 0, y: 0, RGBA(r: 1, g: 1, b: 1, a: 1))
        let surface = try cpu.surface(buffer)
        for (amount, threshold) in [(.nan, 0), (.infinity, 0), (-.infinity, 0.1), (1, -1), (1, -0.001), (1, .nan),
                                    (1, .infinity), (.nan, -1), (1, 0)] as [(Double, Double)] {
            do {
                _ = try cpu.unsharpMask(surface, amount: amount, sigma: 1, threshold: threshold)
                #expect(throws: Never.self) { try UnsharpRule(amount: amount, threshold: threshold) }
            } catch let expected as RenderError {
                #expect(throws: expected) { try UnsharpRule(amount: amount, threshold: threshold) }
            }
        }
        let huge = try UnsharpRule(amount: 1e300, threshold: 0)
        do {
            _ = try cpu.unsharpMask(surface, amount: 1e300, sigma: 1, threshold: 0)
            Issue.record("the CPU accepts an overflowing amount")
        } catch let expected as RenderError {
            #expect(throws: expected) { try huge.check([0, huge.apply(1, blurred: 0.5)]) }
        }
        #expect(throws: Never.self) { try huge.check([0, 1, -2]) }
    }
}
