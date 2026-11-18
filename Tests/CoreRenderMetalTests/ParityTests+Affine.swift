// ParityTests+Affine.swift: the Metal composite through an AffineMatrix (#829) against the CPU, the
// reference. Every blend mode composites a 512 x 512 soft-alpha layer onto a 1024 x 1024 backdrop through a
// 15 degree turn, a 1.3x scale and a fractional offset at opacity 0.7, bilinear: the GPU's pixels match the CPU
// within `.standard` (2 display levels or 1e-3 linear), and every pixel outside `m.writeBounds` is unchanged.
// Skipped without a device; returns early without `.affine` (read-write tier 2 only).
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Foundation
import Metal
import Testing

/// A 15 degree turn and a 1.3x scale, then (`tx`, `ty`).
func turnAndScale(tx: Double, ty: Double) -> AffineMatrix {
    let (cosine, sine) = (1.3 * cos(15 * Double.pi / 180), 1.3 * sin(15 * Double.pi / 180))
    return AffineMatrix(a: cosine, b: sine, c: -sine, d: cosine, tx: tx, ty: ty)
}

extension PixelBuffer {
    /// `seeded` faded by a radial falloff to clear at the edge: premultiplied, so every component scales.
    static func softAlpha(width: Int, height: Int, seed: UInt64) throws -> PixelBuffer {
        var buffer = try seeded(width: width, height: height, seed: seed)
        let (cx, cy, r) = (Float(width) / 2, Float(height) / 2, Float(min(width, height)) / 2)
        for y in 0..<height {
            for x in 0..<width {
                let d = ((Float(x) + 0.5 - cx) * (Float(x) + 0.5 - cx) + (Float(y) + 0.5 - cy) * (Float(y) + 0.5 - cy)).squareRoot()
                let t = max(0, min(1, 1 - d / r)), f = t * t * (3 - 2 * t)
                let p = try buffer.pixel(x: x, y: y)
                try buffer.setPixel(x: x, y: y, RGBA(r: p.r * f, g: p.g * f, b: p.b * f, a: p.a * f))
            }
        }
        return buffer
    }
}

extension ParityTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func affineComposite() throws {
        let metal = try MetalBackend.onDefaultDevice()
        #expect(metal.supports.contains(.affine) == (metal.device.readWriteTextureSupport == .tier2), "#829, on tier 2")
        guard metal.supports.contains(.affine) else { return }
        let layer = try PixelBuffer.softAlpha(width: 512, height: 512, seed: 0x829A)
        let backdrop = try PixelBuffer.seeded(width: 1024, height: 1024, seed: 0x829B)
        let m = turnAndScale(tx: 312.375, ty: 41.625)
        let wb = try #require(m.writeBounds(of: 512, 512, filter: .bilinear))
        var passed = 0
        for mode in BlendMode.allCases {
            let s = try metal.surface(layer)
            var target = try metal.surface(backdrop)
            defer { metal.release(target); metal.release(s) }
            let held = try metal.read(target)
            var expected = held
            try expected.composite(try metal.read(s), through: m, mode: mode, opacity: 0.7, filter: .bilinear)
            try metal.composite(s, onto: &target, through: m, mode: mode, opacity: 0.7, filter: .bilinear)
            let got = try metal.read(target)
            let result = try ParityHarness.compare(got, expected, tolerance: .standard)
            #expect(result.passed, "\(mode): \(result)")
            var outside = 0
            for y in 0..<1024 {
                for x in 0..<1024 where !(wb.x..<(wb.x + wb.width)).contains(x) || !(wb.y..<(wb.y + wb.height)).contains(y) {
                    if try got.pixel(x: x, y: y) != held.pixel(x: x, y: y) { outside += 1 }
                }
            }
            #expect(outside == 0, "\(mode): \(outside) pixels outside writeBounds changed")
            if result.passed, outside == 0 { passed += 1 }
        }
        #expect(passed == BlendMode.allCases.count, "\(passed) of \(BlendMode.allCases.count) modes match the CPU")
        #expect(metal.isHealthy)
    }
}
#endif
