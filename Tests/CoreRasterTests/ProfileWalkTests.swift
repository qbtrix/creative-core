// ProfileWalkTests.swift: KJ-CP, the colour-profiles walk (CP-9). A 16-bit
// PSD built here from the spec's fields embeds a wide-gamut matrix profile
// (primaries chosen for this test, no vendor's) as image resource 1039. It
// opens with that profile; converted into the working space (linear sRGB
// primaries) its pure green, outside sRGB, stays finite and unclipped in
// Float32; saved as 16-bit ORA with the working profile (through the raw test
// `PixelCodec`, which keeps every Float) it reopens `==`; converted to sRGB
// and saved as 8-bit PSD with sRGB embedded it reopens within 1/255 of the
// clipped, encoded colours.
import CoreColor
import CoreRaster
import Foundation
import Testing

@Suite struct ProfileWalkTests {
    static let width = 16, height = 8

    /// A matrix-and-curve profile from xy chromaticities whose white is the D50 PCS white, so the
    /// colourants need no adaptation; values on the ICC grids (s15Fixed16, u8Fixed8 gamma).
    static func profile(_ name: String, red: (Double, Double), green: (Double, Double), blue: (Double, Double),
                        gamma: Double) -> ColorProfile {
        let p = [red, green, blue].map { x, y in [x / y, 1, (1 - x - y) / y] }, white = [0.9642, 1, 0.8249]
        func det(_ a: [Double], _ b: [Double], _ c: [Double]) -> Double {
            a[0] * (b[1] * c[2] - b[2] * c[1]) - a[1] * (b[0] * c[2] - b[2] * c[0]) + a[2] * (b[0] * c[1] - b[1] * c[0])
        }
        // Cramer's rule: the scale of each primary so that RGB (1, 1, 1) lands on the white.
        let d = det(p[0], p[1], p[2])
        let s = [det(white, p[1], p[2]) / d, det(p[0], white, p[2]) / d, det(p[0], p[1], white) / d]
        let m: [Double] = (0..<9).map { (k: Int) -> Double in
            let v: Double = p[k % 3][k / 3] * s[k % 3]
            return (v * 65536).rounded() / 65536
        }
        let curve = ProfileCurve.gamma((gamma * 256).rounded() / 256)
        return ColorProfile(name: name, isGray: false, toXYZD50: m, curves: [curve, curve, curve])
    }

    static let wide = profile("Walk wide gamut", red: (0.70, 0.29), green: (0.16, 0.78), blue: (0.14, 0.04), gamma: 2.2)

    /// Encoded samples: (0, 0) pure green, a transparent pixel at the top right, seeded opaque colour elsewhere.
    static func sample(_ id: Int16, _ x: Int, _ y: Int) -> UInt16 {
        if x == 0 && y == 0 { return id == 1 || id == -1 ? 0xFFFF : 0 }
        if id == -1 { return x == width - 1 && y == 0 ? 0 : 0xFFFF }
        var rng = SplitMix64(seed: UInt64(y * width + x) &* 31 &+ UInt64(id + 2))
        return UInt16.random(in: 0...UInt16.max, using: &rng)
    }

    /// A 16-bit RGB PSD: `resources`, one canvas-sized layer (transparency and colour, raw), and the
    /// merged image with its alpha, every sample big-endian.
    static func deepFile(resources: [UInt8]) -> Data {
        func rows(_ id: Int16) -> [[UInt8]] {
            (0..<height).map { y in (0..<width).flatMap { x in let v = sample(id, x, y); return [UInt8(v >> 8), UInt8(v & 0xFF)] } }
        }
        let record = PSDRecord(name: "Photo", bottom: height, right: width, channels: [-1, 0, 1, 2])
        let channels = record.channels.map { id in
            var b = BigEndian(); b.u16(0); PSDFile.rows(rows(id), rle: false, into: &b); return (id: id, bytes: b.out)
        }
        var w = BigEndian()
        w.ascii("8BPS"); w.u16(1); w.out += [0, 0, 0, 0, 0, 0]
        for v in [4, 0, height, 0, width, 16, 3] { w.u16(v) }
        w.u32(0) // colour mode data
        w.u32(resources.count); w.out += resources
        w.sized { section in
            section.sized(pad: 2) { info in
                info.u16(-1); PSDFile.record(record, channels, into: &info) // the merged alpha is transparency
                channels.forEach { info.out += $0.bytes }
            }
            section.u32(0)
        }
        w.u16(0)
        PSDFile.rows(([0, 1, 2, -1] as [Int16]).flatMap(rows), rle: false, into: &w)
        return Data(w.out)
    }

    /// Every layer's pixels and the composite, through `body`.
    func mapPixels(_ image: LayeredImage, _ body: (PixelBuffer) throws -> PixelBuffer) throws -> LayeredImage {
        var out = image
        out.nodes = try image.nodes.map { node in
            guard case .pixels(var layer) = node else { return node }
            layer.pixels = try body(layer.pixels)
            return .pixels(layer)
        }
        out.composite = try image.composite.map(body)
        return out
    }

    /// Straight colour encoded with the sRGB curve and clipped to 0...1, then alpha: what an 8-bit file can hold.
    func encoded(_ p: RGBA) -> [Double] {
        guard p.a > 0 else { return [0, 0, 0, 0] }
        return [p.r, p.g, p.b].map { min(max(TransferCurve.encode(Double($0 / p.a)), 0), 1) } + [Double(p.a)]
    }

    @Test func walk() throws {
        // The fixture: the profile made with ColorProfile and iccData(), embedded as resource 1039.
        let icc = try Self.wide.iccData()
        #expect(try ColorProfile(iccData: icc) == Self.wide, "the test's profile sits on the ICC grids")
        let opened = try PSD.read(Self.deepFile(resources: psdResource(1039, [UInt8](icc))))

        // 1. It opens 16-bit with its profile, the green as stored.
        #expect(opened.bitsPerChannel == 16 && opened.profile == Self.wide)
        #expect(opened.nodes.count == 1 && opened.composite != nil)
        #expect(try opened.composite?.pixel(x: 0, y: 0) == RGBA(r: 0, g: 1, b: 0, a: 1))

        // 2. Into the working space: the green, outside sRGB, stays finite and unclipped.
        var working = try mapPixels(opened) { try $0.converted(from: Self.wide, to: .linearSRGB) }
        working.profile = .linearSRGB
        let want = try ProfileTransform(from: Self.wide, to: .linearSRGB).apply(Color3(0, 1, 0))
        #expect(min(want.c0, want.c1, want.c2) < -0.05, "the test's green lies outside sRGB: \(want)")
        for buffer in [working.composite, pixelLayer(working.nodes.first)?.pixels] {
            let green = try #require(try buffer?.pixel(x: 0, y: 0))
            #expect(green.isFinite && green.a == 1)
            #expect(abs(Double(green.r) - want.c0) < 1e-5 && abs(Double(green.g) - want.c1) < 1e-5
                    && abs(Double(green.b) - want.c2) < 1e-5, "unclipped: \(green) against \(want)")
            #expect(try buffer?.pixel(x: Self.width - 1, y: 0) == .clear, "a transparent pixel is unchanged")
        }

        // 3. 16-bit ORA with the working profile reopens == at 16 bits, the out-of-gamut green included.
        let ora = try OpenRaster.write(working, pixels: RawPixelCodec())
        let fromORA = try OpenRaster.read(ora, pixels: RawPixelCodec())
        #expect(fromORA.bitsPerChannel == 16 && fromORA.profile == .linearSRGB)
        #expect(fromORA == working)

        // 4. 8-bit PSD converted to sRGB with sRGB embedded reopens within 1/255.
        var display = try mapPixels(working) { try $0.converted(from: .linearSRGB, to: .sRGB) }
        (display.profile, display.bitsPerChannel) = (.sRGB, 8)
        let fromPSD = try PSD.read(PSD.write(display))
        #expect(fromPSD.bitsPerChannel == 8 && fromPSD.profile == .sRGB)
        let pairs = [(display.composite, fromPSD.composite), (pixelLayer(display.nodes.first)?.pixels, pixelLayer(fromPSD.nodes.first)?.pixels)]
        for (sent, back) in pairs {
            let sent = try #require(sent), back = try #require(back)
            #expect(sent.width == Self.width && back.width == Self.width && back.height == Self.height)
            for y in 0..<Self.height {
                for x in 0..<Self.width {
                    let a = encoded(try sent.pixel(x: x, y: y)), b = encoded(try back.pixel(x: x, y: y))
                    #expect(zip(a, b).allSatisfy { abs($0 - $1) <= 1.0 / 255 + 1e-6 }, "(\(x), \(y)): \(b) against \(a)")
                }
            }
        }
        let clipped = encoded(try #require(try fromPSD.composite?.pixel(x: 0, y: 0)))
        #expect(zip(clipped, [0, 1, 0, 1]).allSatisfy { abs($0 - $1) < 1e-6 }, "the green clips to sRGB green: \(clipped)")
    }
}
