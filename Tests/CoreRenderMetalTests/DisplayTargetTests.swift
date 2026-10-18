// DisplayTargetTests.swift: `MetalBackend.display(_:into:x:y:colorSpace:premultiplied:)` writes the bytes
// `display` returns, straight or premultiplied with the CPU's rounding ((c x a + 127) / 255), into rgba8 and
// bgra8 textures at an offset, from resident or evicted tiles, and refuses a surface that would not fit.
// Skipped without a device.
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
}
#endif
