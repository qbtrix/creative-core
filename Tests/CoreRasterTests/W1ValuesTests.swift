// W1ValuesTests.swift: the W1 value types CoreRaster declares for the beta-80
// engines. AffineMatrix.inverse is exact on the identity, nil on a singular
// matrix and composes back to the identity; ColorLUT's checked init refuses a
// size outside 2...65 and a table whose count is not size³; every value is
// Hashable, so equal values hash alike and different ones compare unequal.
import CoreRaster
import Testing

/// `m` after `n`: the matrix that maps a point through `n`, then through `m`.
private func compose(_ m: AffineMatrix, _ n: AffineMatrix) -> AffineMatrix {
    AffineMatrix(a: m.a * n.a + m.c * n.b, b: m.b * n.a + m.d * n.b,
                 c: m.a * n.c + m.c * n.d, d: m.b * n.c + m.d * n.d,
                 tx: m.a * n.tx + m.c * n.ty + m.tx, ty: m.b * n.tx + m.d * n.ty + m.ty)
}

private func isIdentity(_ m: AffineMatrix, within eps: Double) -> Bool {
    let i = AffineMatrix.identity
    return abs(m.a - i.a) <= eps && abs(m.b - i.b) <= eps && abs(m.c - i.c) <= eps
        && abs(m.d - i.d) <= eps && abs(m.tx - i.tx) <= eps && abs(m.ty - i.ty) <= eps
}

/// A value equal to itself hashes alike, and differs from its other.
private func hashesApart<T: Hashable>(_ value: T, _ other: T) -> Bool {
    Set([value, value]).count == 1 && Set([value, other]).count == 2
}

@Suite struct W1ValuesTests {
    @Test func identityInvertsToItself() {
        #expect(AffineMatrix.identity == AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
        #expect(AffineMatrix.identity.inverse == AffineMatrix.identity)
    }

    @Test func singularHasNoInverse() {
        // Rank one: the second column is twice the first.
        #expect(AffineMatrix(a: 1, b: 2, c: 2, d: 4, tx: 5, ty: -3).inverse == nil)
        #expect(AffineMatrix(a: 0, b: 0, c: 0, d: 0, tx: 1, ty: 1).inverse == nil)
        #expect(AffineMatrix(a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0).inverse == nil)
        // A determinant so small its reciprocal overflows has no finite inverse.
        #expect(AffineMatrix(a: 1e-200, b: 0, c: 0, d: 1e-200, tx: 0, ty: 0).inverse == nil)
        // A mirror is not singular: its determinant is negative, not zero.
        let mirror = AffineMatrix(a: -1, b: 0, c: 0, d: 1, tx: 4, ty: 0)
        #expect(mirror.inverse == AffineMatrix(a: -1, b: 0, c: 0, d: 1, tx: 4, ty: 0))
    }

    @Test func scaleRotateInverseComposesToIdentity() throws {
        // Rotate by the angle whose cosine is 0.6 and sine 0.8, scale 2.5 by 0.4.
        let (cosine, sine) = (0.6, 0.8)
        let (sx, sy) = (2.5, 0.4)
        let m = AffineMatrix(a: sx * cosine, b: sx * sine, c: -sy * sine, d: sy * cosine, tx: 13.25, ty: -7.5)
        let inv = try #require(m.inverse)
        #expect(isIdentity(compose(m, inv), within: 1e-12))
        #expect(isIdentity(compose(inv, m), within: 1e-12))
    }

    @Test func refusesSizeOutside2To65() throws {
        #expect(throws: RasterError.self) { try ColorLUT(size: 1, table: [SIMD3<Float>(0, 0, 0)]) }
        #expect(throws: RasterError.self) {
            try ColorLUT(size: 66, table: Array(repeating: SIMD3<Float>(0, 0, 0), count: 66 * 66 * 66))
        }
        #expect(throws: RasterError.self) { try ColorLUT(size: 0, table: []) }
        #expect(throws: RasterError.self) { try ColorLUT(size: Int.max, table: []) }
        let small = try ColorLUT(size: 2, table: Array(repeating: SIMD3<Float>(0.5, 0.5, 0.5), count: 8))
        #expect(small.size == 2 && small.table.count == 8)
        let large = try ColorLUT(size: 65, table: Array(repeating: SIMD3<Float>(0, 1, 0), count: 65 * 65 * 65))
        #expect(large.size == 65 && large.table.count == 274_625)
    }

    @Test func refusesShortTable() {
        let entry = SIMD3<Float>(0.25, 0.5, 0.75)
        #expect(throws: RasterError.self) { try ColorLUT(size: 3, table: Array(repeating: entry, count: 26)) }
        #expect(throws: RasterError.self) { try ColorLUT(size: 3, table: []) }
        // A long table is as wrong as a short one: size³ exactly.
        #expect(throws: RasterError.self) { try ColorLUT(size: 3, table: Array(repeating: entry, count: 28)) }
        #expect(throws: Never.self) { try ColorLUT(size: 3, table: Array(repeating: entry, count: 27)) }
    }

    @Test func refusesNonFiniteEntry() {
        var table = Array(repeating: SIMD3<Float>(0, 0, 0), count: 8)
        table[5] = SIMD3<Float>(0, .nan, 0)
        #expect(throws: RasterError.self) { try ColorLUT(size: 2, table: table) }
        table[5] = SIMD3<Float>(0, 0, .infinity)
        #expect(throws: RasterError.self) { try ColorLUT(size: 2, table: table) }
    }

    @Test func everyValueIsHashable() throws {
        let red = RGBA(r: 1, g: 0, b: 0, a: 1)
        let blue = RGBA(r: 0, g: 0, b: 1, a: 1)
        #expect(hashesApart(AffineMatrix.identity, AffineMatrix(a: 2, b: 0, c: 0, d: 2, tx: 0, ty: 0)))
        #expect(hashesApart(FlipAxis.horizontal, .vertical))
        #expect(hashesApart(CanvasAnchor.topLeft, .bottomRight))
        #expect(hashesApart(MatteSource.alpha, .luminance))
        let range = HSLRange(hue: 10, saturation: -20, lightness: 5)
        #expect(hashesApart(range, HSLRange()))
        #expect(hashesApart(HSLAdjustment(reds: range), HSLAdjustment()))
        #expect(hashesApart(GrayMix(reds: 40, yellows: 60, greens: 40, cyans: 60, blues: 20, magentas: 80, tint: red),
                            GrayMix(reds: 40, yellows: 60, greens: 40, cyans: 60, blues: 20, magentas: 80, tint: nil)))
        let channels = ChannelMatrix(red: SIMD4(1, 0, 0, 0), green: SIMD4(0, 1, 0, 0), blue: SIMD4(0, 0, 1, 0),
                                     monochrome: false)
        var mono = channels
        mono.monochrome = true
        #expect(hashesApart(channels, mono))
        let balance = ToneBalance(shadows: SIMD3(0.1, 0, 0), midtones: .zero, highlights: .zero, preserveLuminosity: true)
        #expect(hashesApart(balance, ToneBalance(shadows: .zero, midtones: .zero, highlights: .zero,
                                                 preserveLuminosity: true)))
        #expect(hashesApart(GradientMapStop(offset: 0, color: red), GradientMapStop(offset: 0, color: blue)))
        let lut = try ColorLUT(size: 2, table: Array(repeating: SIMD3<Float>(0, 0, 0), count: 8))
        let other = try ColorLUT(size: 2, table: Array(repeating: SIMD3<Float>(1, 1, 1), count: 8))
        #expect(hashesApart(lut, other))
        #expect(hashesApart(LayerEffect.boxBlur(radius: 2), .boxBlur(radius: 3)))
        #expect(hashesApart(LayerEffect.stroke(color: red, width: 2, position: .inside),
                            .stroke(color: red, width: 2, position: .outside)))
        #expect(hashesApart(LayerEffect.glow(color: red, radius: 4, intensity: 1, inner: false),
                            .shadow(color: red, dx: 0, dy: 0, blur: 4, inner: false)))
        #expect(hashesApart(StrokePosition.outside, .center))
        #expect(hashesApart(FillTolerance.exact, .within(0)))
        #expect(hashesApart(FillTolerance.within(0.1), .within(0.2)))
        #expect(hashesApart(RasterGradientShape.linear, .diamond))
    }
}
