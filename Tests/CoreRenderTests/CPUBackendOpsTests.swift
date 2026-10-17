// CPUBackendOpsTests.swift: render-backend RB-4's acceptance. Each CPUBackend op of
// the transform, resample, blur, adjust and retouch families equals the CoreRaster
// call it wraps with `==` on seeded buffers (crop, every quarter turn, both resample
// filters, blur, unsharp, every ToneAdjustment case with both encodings where it
// has one, and a clone through a soft mask), returns a new surface and leaves its
// input alone; every CoreRaster throw surfaces as `.raster` with the same message;
// released and foreign surfaces throw `surfaceMismatch`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreRaster
@testable import CoreRender
import Testing

/// A `width` x `height` buffer of seeded sRGB bytes.
private func seededBuffer(width: Int, height: Int, seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    let bytes = (0..<width * height * 4).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
    return try PixelBuffer(rgba8: bytes, width: width, height: height)
}

/// The message of the CoreRaster error `body` throws, or "" when it returns.
private func rasterMessage(_ body: () throws -> PixelBuffer) -> String {
    do { _ = try body() } catch let RasterError.invalid(message) { return message } catch {}
    return ""
}

/// `op` run on a new surface of `buffer`: checks it made a new surface of its
/// pixels' size and left the input unchanged, releases both, returns the pixels.
private func run(_ cpu: CPUBackend, _ buffer: PixelBuffer,
                 _ op: (RenderSurface) throws -> RenderSurface) throws -> PixelBuffer {
    let s = try cpu.surface(buffer)
    defer { cpu.release(s) }
    let out = try op(s)
    defer { cpu.release(out) }
    let pixels = try cpu.read(out)
    #expect(out.id != s.id && out.backend == cpu.name)
    #expect(out.width == pixels.width && out.height == pixels.height)
    #expect(try cpu.read(s) == buffer)
    return pixels
}

@Suite struct CPUBackendOpsTests {
    let cpu = CPUBackend()

    @Test func cropAndRotateEqualCoreRaster() throws {
        let buffer = try seededBuffer(width: 7, height: 5, seed: 41)
        for (x, y, w, h) in [(0, 0, 7, 5), (2, 1, 3, 4), (6, 4, 1, 1), (1, 3, 5, 2)] {
            let got = try run(cpu, buffer) { try cpu.cropped($0, x: x, y: y, width: w, height: h) }
            #expect(got == (try buffer.cropped(x: x, y: y, width: w, height: h)), "crop \(x),\(y) \(w)x\(h)")
        }
        for turn in [QuarterTurn.degrees90, .degrees180, .degrees270] {
            #expect(try run(cpu, buffer) { try cpu.rotated($0, turn) } == buffer.rotated(turn), "\(turn)")
        }
    }

    @Test func resampleEqualsCoreRasterForBothFilters() throws {
        let buffer = try seededBuffer(width: 7, height: 5, seed: 42)
        for filter in [ResampleFilter.bilinear, .lanczos3] {
            for (w, h) in [(13, 4), (3, 9), (7, 5), (1, 1)] {
                let got = try run(cpu, buffer) { try cpu.resampled($0, width: w, height: h, filter: filter) }
                #expect(got == (try buffer.resized(width: w, height: h, filter: filter)), "\(filter) \(w)x\(h)")
            }
        }
    }

    @Test func blurAndUnsharpEqualCoreRaster() throws {
        let buffer = try seededBuffer(width: 9, height: 6, seed: 43)
        for sigma in [0, 0.6, 1.5, 3] {
            #expect(try run(cpu, buffer) { try cpu.gaussianBlur($0, sigma: sigma) } == buffer.gaussianBlur(sigma: sigma))
        }
        for (amount, sigma, threshold) in [(0.8, 1.2, 0.05), (2.0, 0.7, 0.0), (-0.5, 2.5, 0.1)] {
            let got = try run(cpu, buffer) { try cpu.unsharpMask($0, amount: amount, sigma: sigma, threshold: threshold) }
            #expect(got == (try buffer.unsharpMask(amount: amount, sigma: sigma, threshold: threshold)), "\(amount) \(sigma) \(threshold)")
        }
    }

    @Test func everyToneAdjustmentEqualsItsCoreRasterCall() throws {
        let buffer = try seededBuffer(width: 6, height: 5, seed: 44)
        let points = [CurvePoint(x: 0, y: 0.05), CurvePoint(x: 0.4, y: 0.6), CurvePoint(x: 1, y: 0.9)]
        let cases: [(ToneAdjustment, PixelBuffer)] = [
            (.exposure(stops: 0.7), try buffer.exposure(stops: 0.7)),
            (.exposure(stops: -1.3), try buffer.exposure(stops: -1.3)),
            (.levels(inBlack: 0.05, inWhite: 0.9, gamma: 1.6, outBlack: 0.02, outWhite: 0.95),
             try buffer.levels(inBlack: 0.05, inWhite: 0.9, gamma: 1.6, outBlack: 0.02, outWhite: 0.95)),
            (.levels(inBlack: 0.1, inWhite: 0.8, gamma: 0.7, outBlack: 0, outWhite: 1, encoding: .sRGB),
             try buffer.levels(inBlack: 0.1, inWhite: 0.8, gamma: 0.7, outBlack: 0, outWhite: 1, encoding: .sRGB)),
            (.curves(points: points), try buffer.curves(points: points)),
            (.curves(points: points, encoding: .sRGB), try buffer.curves(points: points, encoding: .sRGB)),
            (.whiteBalance(temperature: 35, tint: -20), try buffer.whiteBalance(temperature: 35, tint: -20)),
            (.contrast(40), try buffer.contrast(40)),
            (.contrast(-25), try buffer.contrast(-25)),
            (.highlightsShadows(highlights: -30, shadows: 55), try buffer.highlightsShadows(highlights: -30, shadows: 55)),
        ]
        for (adjustment, expected) in cases {
            #expect(expected != buffer, "\(adjustment) is not an identity")
            #expect(try run(cpu, buffer) { try cpu.adjusted($0, adjustment) } == expected, "\(adjustment)")
        }
    }

    @Test func cloneThroughASoftMaskEqualsCoreRaster() throws {
        let buffer = try seededBuffer(width: 9, height: 7, seed: 45)
        let mask = try Mask.ellipse(width: 9, height: 7, centerX: 4.3, centerY: 3.6, radiusX: 3.2, radiusY: 2.4)
        for (dx, dy) in [(2, 1), (-3, 0), (0, -2), (-1, 2), (9, 0)] {
            let got = try run(cpu, buffer) { try cpu.cloned($0, offset: (dx: dx, dy: dy), through: mask) }
            #expect(got == (try buffer.cloned(offset: (dx: dx, dy: dy), through: mask)), "\(dx),\(dy)")
        }
    }

    @Test func everyCoreRasterThrowSurfacesAsRasterWithItsMessage() throws {
        let b = try seededBuffer(width: 5, height: 4, seed: 46)
        let s = try cpu.surface(b)
        let small = try Mask(width: 3, height: 3, fill: 1)
        let cases: [(String, () throws -> PixelBuffer, () throws -> RenderSurface)] = [
            ("crop off the left", { try b.cropped(x: -1, y: 0, width: 2, height: 2) }, { try cpu.cropped(s, x: -1, y: 0, width: 2, height: 2) }),
            ("crop too wide", { try b.cropped(x: 1, y: 0, width: 5, height: 2) }, { try cpu.cropped(s, x: 1, y: 0, width: 5, height: 2) }),
            ("resample to 0", { try b.resized(width: 0, height: 3, filter: .bilinear) }, { try cpu.resampled(s, width: 0, height: 3, filter: .bilinear) }),
            ("blur sigma -1", { try b.gaussianBlur(sigma: -1) }, { try cpu.gaussianBlur(s, sigma: -1) }),
            ("blur sigma nan", { try b.gaussianBlur(sigma: .nan) }, { try cpu.gaussianBlur(s, sigma: .nan) }),
            ("unsharp amount inf", { try b.unsharpMask(amount: .infinity, sigma: 1, threshold: 0) },
             { try cpu.unsharpMask(s, amount: .infinity, sigma: 1, threshold: 0) }),
            ("unsharp threshold -1", { try b.unsharpMask(amount: 1, sigma: 1, threshold: -1) },
             { try cpu.unsharpMask(s, amount: 1, sigma: 1, threshold: -1) }),
            ("exposure nan", { try b.exposure(stops: .nan) }, { try cpu.adjusted(s, .exposure(stops: .nan)) }),
            ("levels black over white", { try b.levels(inBlack: 0.9, inWhite: 0.1, gamma: 1, outBlack: 0, outWhite: 1) },
             { try cpu.adjusted(s, .levels(inBlack: 0.9, inWhite: 0.1, gamma: 1, outBlack: 0, outWhite: 1)) }),
            ("levels gamma 0", { try b.levels(inBlack: 0, inWhite: 1, gamma: 0, outBlack: 0, outWhite: 1) },
             { try cpu.adjusted(s, .levels(inBlack: 0, inWhite: 1, gamma: 0, outBlack: 0, outWhite: 1)) }),
            ("curves one point", { try b.curves(points: [CurvePoint(x: 0.5, y: 0.5)]) },
             { try cpu.adjusted(s, .curves(points: [CurvePoint(x: 0.5, y: 0.5)])) }),
            ("white balance tint 101", { try b.whiteBalance(temperature: 0, tint: 101) },
             { try cpu.adjusted(s, .whiteBalance(temperature: 0, tint: 101)) }),
            ("contrast 200", { try b.contrast(200) }, { try cpu.adjusted(s, .contrast(200)) }),
            ("shadows -101", { try b.highlightsShadows(highlights: 0, shadows: -101) },
             { try cpu.adjusted(s, .highlightsShadows(highlights: 0, shadows: -101)) }),
            ("clone mask size", { try b.cloned(offset: (dx: 1, dy: 0), through: small) },
             { try cpu.cloned(s, offset: (dx: 1, dy: 0), through: small) }),
        ]
        for (name, direct, op) in cases {
            let message = rasterMessage(direct)
            #expect(!message.isEmpty, "\(name) throws in CoreRaster")
            #expect(throws: RenderError.raster(message), "\(name)") { try op() }
        }
        #expect(try cpu.read(s) == b)
    }

    @Test func releasedAndForeignSurfacesThrowMismatch() throws {
        let buffer = try seededBuffer(width: 4, height: 4, seed: 47)
        let released = try cpu.surface(buffer)
        cpu.release(released)
        let foreign = try FakeBackend(supports: Set(RenderOp.allCases)).surface(buffer)
        let mask = try Mask(width: 4, height: 4, fill: 1)
        for s in [released, foreign] {
            #expect(throws: RenderError.surfaceMismatch) { try cpu.cropped(s, x: 0, y: 0, width: 2, height: 2) }
            #expect(throws: RenderError.surfaceMismatch) { try cpu.rotated(s, .degrees90) }
            #expect(throws: RenderError.surfaceMismatch) { try cpu.resampled(s, width: 2, height: 2, filter: .lanczos3) }
            #expect(throws: RenderError.surfaceMismatch) { try cpu.gaussianBlur(s, sigma: 1) }
            #expect(throws: RenderError.surfaceMismatch) { try cpu.unsharpMask(s, amount: 1, sigma: 1, threshold: 0) }
            #expect(throws: RenderError.surfaceMismatch) { try cpu.adjusted(s, .contrast(10)) }
            #expect(throws: RenderError.surfaceMismatch) { try cpu.cloned(s, offset: (dx: 1, dy: 0), through: mask) }
        }
    }
}
