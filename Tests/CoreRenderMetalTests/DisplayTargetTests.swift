// DisplayTargetTests.swift: `MetalBackend.display(_:into:x:y:colorSpace:premultiplied:)` writes the bytes
// `display` returns, straight or premultiplied with the CPU's rounding ((c x a + 127) / 255), into rgba8 and
// bgra8 textures at an offset, from resident or evicted tiles, and refuses a surface that would not fit.
// With a ToneProgram it writes, within `ParityTolerance.standard`'s bytes, what the CPU displays after running
// the program's adjustments one after another on the GPU's pixels: hue/saturation, sRGB levels and curves,
// exposure, vibrance and the chains a live Photo slider runs, on the parity samples and a tiled image, resident and
// evicted, colour matrices included; `adjusted(_:tone:)` (an adjustment layer under other layers) matches the
// CPU backend's within `.standard` on the same images. Skipped without a device.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Metal
import Testing

/// An `rgba8Unorm` or `bgra8Unorm` shared texture of `width` x `height` with shaderWrite usage.
private func target(_ metal: MetalBackend, _ format: MTLPixelFormat, width: Int, height: Int) throws -> any MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = metal.device.hasUnifiedMemory ? .shared : .managed
    return try #require(metal.device.makeTexture(descriptor: descriptor))
}

/// The `width` x `height` region of `texture` at (`x`, `y`) as RGBA bytes (bgra8 swizzled back).
private func bytes(of texture: any MTLTexture, x: Int, y: Int, width: Int, height: Int) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: width * height * 4)
    out.withUnsafeMutableBytes { raw in
        if let base = raw.baseAddress {
            texture.getBytes(base, bytesPerRow: width * 4, from: MTLRegionMake2D(x, y, width, height), mipmapLevel: 0)
        }
    }
    guard texture.pixelFormat == .bgra8Unorm else { return out }
    for i in stride(from: 0, to: out.count, by: 4) { out.swapAt(i, i + 2) }
    return out
}

@Suite(.serialized) struct DisplayTargetTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func displayIntoATextureWritesTheDisplayBytes() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let buffer = try PixelBuffer.seeded(width: 300, height: 270, seed: 0xD15)
        let s = try metal.surface(buffer)
        let straight = try metal.display(s, colorSpace: .sRGB)
        var premultiplied = straight
        for i in stride(from: 0, to: premultiplied.count, by: 4) where premultiplied[i + 3] != 255 {
            let a = UInt32(premultiplied[i + 3])
            for c in i..<(i + 3) { premultiplied[c] = UInt8((UInt32(premultiplied[c]) * a + 127) / 255) }
        }
        for format: MTLPixelFormat in [.rgba8Unorm, .bgra8Unorm] {
            let texture = try target(metal, format, width: 320, height: 300)
            try metal.display(s, into: texture, x: 11, y: 17, colorSpace: .sRGB, premultiplied: false)
            #expect(bytes(of: texture, x: 11, y: 17, width: 300, height: 270) == straight, "\(format.rawValue) straight")
            try metal.display(s, into: texture, x: 11, y: 17, colorSpace: .sRGB, premultiplied: true)
            #expect(bytes(of: texture, x: 11, y: 17, width: 300, height: 270) == premultiplied, "\(format.rawValue) premultiplied")
        }
        metal.budgetBytes = 0
        let texture = try target(metal, .rgba8Unorm, width: 300, height: 270)
        try metal.display(s, into: texture, x: 0, y: 0, colorSpace: .sRGB, premultiplied: false)
        #expect(bytes(of: texture, x: 0, y: 0, width: 300, height: 270) == straight, "evicted")
        #expect(throws: RenderError.self) { try metal.display(s, into: texture, x: 1, y: 0, colorSpace: .sRGB, premultiplied: false) }
    }

    static let matrix = ToneProgram.Operation.matrix(rows: [0.6, 0.5, -0.1, -0.2, 1.1, 0.1, 0.3, -0.4, 1.1], lightness: 0.25)

    static let chains: [[ToneProgram.Operation]] = {
        let levels = ToneAdjustment.levels(inBlack: 0.05, inWhite: 0.8, gamma: 1.4, outBlack: 0, outWhite: 1, encoding: .sRGB)
        let curves = ToneAdjustment.curves(
            points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.62), CurvePoint(x: 1, y: 1)], encoding: .sRGB)
        let adjustments: [[ToneAdjustment]] = [
            [.hueSaturation(hue: 40, saturation: -30, lightness: 0)], [.hueSaturation(hue: -150, saturation: 60, lightness: 25)],
            [levels], [curves], [.exposure(stops: 0.7)],
            [.exposure(stops: -0.5), levels, curves, .hueSaturation(hue: 20, saturation: 35, lightness: -10)],
            [levels, .hueSaturation(hue: 0, saturation: -100, lightness: 0), .exposure(stops: 1), curves],
            [.vibrance(60)], [.vibrance(-40)], [.exposure(stops: 0.3), levels, .vibrance(100), curves],
        ]
        return adjustments.map { $0.map(ToneProgram.Operation.adjustment) }
            + [[matrix], [.adjustment(.exposure(stops: 0.4)), .adjustment(levels), matrix, .adjustment(curves)]]
    }()

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func aToneProgramMatchesTheCPUChainThenDisplay() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let cpu = CPUBackend()
        var images = try ParityHarness.sampleSet(for: .adjust).map { ($0.name, $0.source, false) }
        let tiled = try PixelBuffer.seeded(width: 300, height: 270, seed: 0x70E)
        images += [("300x270", tiled, false), ("300x270 evicted", tiled, true)]
        let budget = metal.budgetBytes
        defer { metal.budgetBytes = budget }
        for (name, image, evict) in images {
            let s = try metal.surface(image)
            defer { metal.release(s) }
            let held = try metal.read(s)
            metal.budgetBytes = evict ? 0 : budget
            let texture = try target(metal, .rgba8Unorm, width: image.width, height: image.height)
            for chain in Self.chains {
                let program = try ToneProgram(operations: chain)
                let want = try cpu.adjusted(cpu.surface(held), tone: program)
                let plain = chain.compactMap { if case .adjustment(let a) = $0 { a } else { nil } }
                if plain.count == chain.count {
                    // A chain of adjustments: the program's CPU map is the CPU's adjustments one after another.
                    var steps = try cpu.surface(held)
                    for adjustment in plain { steps = try cpu.adjusted(steps, adjustment) }
                    let result = try ParityHarness.compare(try cpu.read(want), try cpu.read(steps), tolerance: .standard)
                    #expect(result.passed, "\(name) \(chain) CPU map vs CPU chain: \(result)")
                }
                let gpu = try metal.adjusted(s, tone: program)
                let adjusted = try ParityHarness.compare(try metal.read(gpu), try cpu.read(want), tolerance: .standard)
                metal.release(gpu)
                #expect(adjusted.passed, "\(name) \(chain) adjusted(tone:): \(adjusted)")
                var expected = try cpu.display(want, colorSpace: .sRGB)
                for i in stride(from: 0, to: expected.count, by: 4) where expected[i + 3] != 255 {
                    let a = UInt32(expected[i + 3])
                    for c in i..<(i + 3) { expected[c] = UInt8((UInt32(expected[c]) * a + 127) / 255) }
                }
                try metal.display(s, into: texture, x: 0, y: 0, colorSpace: .sRGB, premultiplied: true, tone: program)
                let got = bytes(of: texture, x: 0, y: 0, width: image.width, height: image.height)
                let worst = zip(got, expected).map { abs(Int($0) - Int($1)) }.max() ?? 0
                #expect(worst <= Int(ParityTolerance.standard.bytes), "\(name) \(chain): worst \(worst)")
            }
        }
        #expect(metal.isHealthy)
    }
}
#endif
