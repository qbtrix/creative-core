// RenderBackendFakeTests.swift: render-backend slice RB-a's acceptance. FakeBackend's
// call log, its gating by op family, its SurfaceStore (round trip, released, foreign and
// wrong-size surfaces), copies sharing the log, concurrent recording, and the two shared
// mappings. engine-contracts EC-3: the five W1 calls recorded with their arguments (the
// mask offset included), and each W1 family, `.color` tone cases among them, gated by
// `supports`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreRaster
import CoreRender
import Testing

/// A `width` x `height` buffer of seeded sRGB bytes.
private func seededBuffer(width: Int, height: Int, seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    let bytes = (0..<width * height * 4).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
    return try PixelBuffer(rgba8: bytes, width: width, height: height)
}

@Suite struct RenderBackendFakeTests {
    @Test func recordsACompositeAndRefusesABlurItDoesNotSupport() throws {
        let fake = FakeBackend(supports: [.composite])
        let source = try fake.surface(try seededBuffer(width: 4, height: 3, seed: 1))
        let backdropBuffer = try seededBuffer(width: 4, height: 3, seed: 2)
        var backdrop = try fake.surface(backdropBuffer)
        let backdropID = backdrop.id
        try fake.composite(source, onto: &backdrop, x: 1, y: 0, mode: .normal, opacity: 0.5)
        #expect(backdrop.id == backdropID)
        #expect(try fake.read(backdrop) == backdropBuffer)
        #expect(throws: RenderError.unsupported(.blur)) { try fake.gaussianBlur(source, sigma: 2) }
        #expect(fake.calls == [.surface(width: 4, height: 3), .surface(width: 4, height: 3),
                               .op(.composite), .read(backdrop), .op(.blur)])
    }

    @Test func compositeIsGatedByTheFamilyOfItsBlendMode() throws {
        let fake = FakeBackend(supports: [.composite])
        let s = try fake.surface(try PixelBuffer(width: 2, height: 2))
        var b = try fake.surface(try PixelBuffer(width: 2, height: 2))
        #expect(throws: RenderError.unsupported(.blendNonSeparable)) { try fake.composite(s, onto: &b, x: 0, y: 0, mode: .luminosity, opacity: 1) }
        #expect(throws: RenderError.unsupported(.blendSeparable)) { try fake.composite(s, onto: &b, x: 0, y: 0, mode: .multiply, opacity: 1) }
        #expect(fake.calls.suffix(2) == [.op(.blendNonSeparable), .op(.blendSeparable)])
    }

    @Test func blendModesMapToTheirFamilies() {
        let nonSeparable: Set<BlendMode> = [.hue, .saturation, .color, .luminosity]
        for mode in BlendMode.allCases {
            let expected: RenderOp = mode == .normal ? .composite
                : nonSeparable.contains(mode) ? .blendNonSeparable : .blendSeparable
            #expect(RenderOp(compositing: mode) == expected, "\(mode)")
        }
        #expect(RenderError(RasterError.invalid("too big")) == .raster("too big"))
    }

    @Test func mappingRethrowsRasterErrorsAndPassesOthersThrough() throws {
        var expected = ""
        do { _ = try PixelBuffer(width: 0, height: 1) } catch let RasterError.invalid(message) { expected = message }
        #expect(!expected.isEmpty)
        #expect(throws: RenderError.raster(expected)) { try RenderError.mapping { try PixelBuffer(width: 0, height: 1) } }
        #expect(throws: RenderError.surfaceMismatch) { try RenderError.mapping { throw RenderError.surfaceMismatch } }
        #expect(try RenderError.mapping { 7 } == 7)
    }

    @Test func readGivesBackTheBufferAndOpsGiveNewSurfaces() throws {
        let fake = FakeBackend(supports: Set(RenderOp.allCases))
        let buffer = try seededBuffer(width: 6, height: 4, seed: 7)
        let s = try fake.surface(buffer)
        #expect(s.backend == "fake" && s.width == 6 && s.height == 4)
        #expect(try fake.read(s) == buffer)
        let crop = try fake.cropped(s, x: 1, y: 1, width: 3, height: 2)
        #expect(try fake.read(crop) == (try buffer.cropped(x: 1, y: 1, width: 3, height: 2)))
        #expect(try fake.read(try fake.rotated(s, .degrees90)) == buffer.rotated(.degrees90))
        #expect(try fake.resampled(s, width: 3, height: 2, filter: .bilinear).width == 3)
        let blurred = try fake.gaussianBlur(s, sigma: 1)
        #expect(blurred.id != s.id)
        #expect(try fake.read(blurred) == buffer)
        #expect(try fake.display(s, colorSpace: .sRGB) == (try buffer.rgba8(colorSpace: .sRGB)))
        let error = #expect(throws: RenderError.self) { try fake.cropped(s, x: 5, y: 0, width: 3, height: 2) }
        guard case .raster(let message)? = error else { Issue.record("not a raster error: \(String(describing: error))"); return }
        #expect(!message.isEmpty)
    }

    @Test func aReleasedSurfaceThrowsSurfaceMismatch() throws {
        let fake = FakeBackend(supports: [.blur])
        let s = try fake.surface(try PixelBuffer(width: 2, height: 2))
        fake.release(s)
        #expect(throws: RenderError.surfaceMismatch) { try fake.read(s) }
        #expect(throws: RenderError.surfaceMismatch) { try fake.gaussianBlur(s, sigma: 1) }
        fake.release(s)
        #expect(fake.calls.suffix(4) == [.release(s), .read(s), .op(.blur), .release(s)])
    }

    @Test func aSurfaceOfAnotherBackendThrowsSurfaceMismatch() throws {
        let fake = FakeBackend(supports: [.composite])
        let other = FakeBackend(name: "other", supports: [.composite])
        let foreign = try other.surface(try PixelBuffer(width: 2, height: 2))
        #expect(throws: RenderError.surfaceMismatch) { try fake.read(foreign) }
        let renamed = RenderSurface(id: foreign.id, width: 2, height: 2, backend: "fake")
        #expect(throws: RenderError.surfaceMismatch) { try fake.read(renamed) }
        let own = try fake.surface(try PixelBuffer(width: 2, height: 2))
        var backdrop = foreign
        #expect(throws: RenderError.surfaceMismatch) {
            try fake.composite(own, onto: &backdrop, x: 0, y: 0, mode: .normal, opacity: 1)
        }
        fake.release(foreign)
        #expect(try other.read(foreign) == (try PixelBuffer(width: 2, height: 2)))
        let ownAsOther = RenderSurface(id: own.id, width: 2, height: 2, backend: "other")
        #expect(throws: RenderError.surfaceMismatch) { try fake.read(ownAsOther) }
        fake.release(ownAsOther)
        #expect(try fake.read(own) == (try PixelBuffer(width: 2, height: 2)), "a foreign-named release frees nothing")
    }

    @Test func aHandleOfTheWrongSizeThrowsSurfaceMismatch() throws {
        let fake = FakeBackend(supports: [.composite])
        let own = try fake.surface(try PixelBuffer(width: 3, height: 2))
        let wider = RenderSurface(id: own.id, width: own.width + 1, height: own.height, backend: own.backend)
        #expect(throws: RenderError.surfaceMismatch) { try fake.read(wider) }
        let taller = RenderSurface(id: own.id, width: own.width, height: own.height + 1, backend: own.backend)
        #expect(throws: RenderError.surfaceMismatch) { try fake.read(taller) }
        #expect(try fake.read(own) == (try PixelBuffer(width: 3, height: 2)), "the right size still reads")
    }

    @Test func copiesShareTheLogAndTheSurfaces() throws {
        let fake = FakeBackend(supports: [.adjust], healthy: false)
        var copy = fake
        copy.healthy = true
        copy.supports = []
        let s = try copy.surface(try PixelBuffer(width: 1, height: 1))
        _ = try fake.adjusted(s, .contrast(10))
        #expect(throws: RenderError.unsupported(.adjust)) { try copy.adjusted(s, .contrast(10)) }
        #expect(copy.isHealthy && !fake.isHealthy)
        #expect(fake.calls == copy.calls)
        #expect(fake.calls == [.surface(width: 1, height: 1), .op(.adjust), .op(.adjust)])
    }

    @Test func concurrentCallsAreAllRecorded() async throws {
        let fake = FakeBackend(supports: [.composite, .transform])
        let tasks = 8, perTask = 50
        try await withThrowingTaskGroup(of: Void.self) { group in
            for t in 0..<tasks {
                group.addTask {
                    var rng = SplitMix64(seed: UInt64(t))
                    for _ in 0..<perTask {
                        let side = Int.random(in: 1...4, using: &rng)
                        fake.release(try fake.surface(try PixelBuffer(width: side, height: side)))
                    }
                }
            }
        }
        #expect(fake.calls.count == tasks * perTask * 2)
        #expect(fake.calls.filter { if case .surface = $0 { true } else { false } }.count == tasks * perTask)
    }

    @Test func w1RecordsArguments() throws {
        let fake = FakeBackend(supports: Set(RenderOp.allCases))
        let buffer = try seededBuffer(width: 4, height: 3, seed: 11)
        let s = try fake.surface(buffer)
        let backdropBuffer = try seededBuffer(width: 4, height: 3, seed: 12)
        var b = try fake.surface(backdropBuffer)
        let backdropID = b.id
        let mask = try Mask(width: 2, height: 3)
        let m = AffineMatrix(a: 0, b: 1, c: -1, d: 0, tx: 3, ty: 0)
        let effect = LayerEffect.motionBlur(degrees: 30, distance: 4)
        try fake.composite(s, onto: &b, x: 1, y: -2, mode: .multiply, opacity: 0.75, mask: mask, maskX: 3, maskY: -4)
        let moved = try fake.transformed(s, m, width: 3, height: 5, filter: .lanczos3)
        let mirrored = try fake.flipped(s, .vertical)
        try fake.composite(s, onto: &b, through: m, mode: .screen, opacity: 0.25, filter: .bilinear)
        let lit = try fake.applying(s, effect)
        let vivid = try fake.adjusted(s, .vibrance(20))
        #expect(Array(fake.calls.dropFirst(2)) == [
            .maskedComposite(x: 1, y: -2, mode: .multiply, opacity: 0.75, mask: mask, maskX: 3, maskY: -4),
            .transformed(m, width: 3, height: 5, filter: .lanczos3),
            .flipped(.vertical),
            .compositeThrough(m, mode: .screen, opacity: 0.25, filter: .bilinear),
            .applying(effect),
            .op(.color),
        ])
        #expect(b.id == backdropID)
        #expect(try fake.read(b) == backdropBuffer, "the fake leaves a backdrop alone")
        #expect(moved.width == 3 && moved.height == 5, "transformed has the asked size")
        for out in [mirrored, lit, vivid] {
            #expect(out.id != s.id)
            #expect(try fake.read(out) == buffer, "a new surface with the pixels unchanged")
        }
    }

    @Test func w1HonoursSupports() throws {
        for family in [RenderOp.maskedComposite, .affine, .effect, .color] {
            let fake = FakeBackend(supports: Set(RenderOp.allCases).subtracting([family]))
            let s = try fake.surface(try PixelBuffer(width: 2, height: 2))
            let backdrop = try fake.surface(try PixelBuffer(width: 2, height: 2))
            var b = backdrop
            let mask = try Mask(width: 1, height: 1)
            let calls: [(family: RenderOp, call: () throws -> Void)] = [
                (.maskedComposite, { try fake.composite(s, onto: &b, x: 0, y: 0, mode: .normal, opacity: 1, mask: mask, maskX: 0, maskY: 0) }),
                (.affine, { _ = try fake.transformed(s, .identity, width: 2, height: 2, filter: .bilinear) }),
                (.affine, { _ = try fake.flipped(s, .horizontal) }),
                (.affine, { try fake.composite(s, onto: &b, through: .identity, mode: .normal, opacity: 1, filter: .bilinear) }),
                (.effect, { _ = try fake.applying(s, .boxBlur(radius: 1)) }),
                (.color, { _ = try fake.adjusted(s, .invert) }),
                (.adjust, { _ = try fake.adjusted(s, .contrast(10)) }),
            ]
            for (op, call) in calls {
                if op == family {
                    #expect(throws: RenderError.unsupported(family)) { try call() }
                } else {
                    #expect(throws: Never.self, "\(op) with \(family) unlisted") { try call() }
                }
            }
            #expect(fake.calls.count == 2 + calls.count, "a refused call is still recorded")
            #expect(b == backdrop)
        }
        let none = FakeBackend(supports: [])
        let s = try none.surface(try PixelBuffer(width: 1, height: 1))
        #expect(throws: RenderError.unsupported(.affine)) { try none.flipped(s, .vertical) }
        #expect(none.calls.last == .flipped(.vertical), "recorded before it is refused")
    }
}
