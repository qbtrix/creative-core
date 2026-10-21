// PSDEffectsClampTests.swift: hostile and edge values in a PSD layer's
// effects (layer-style-engine, Anatomy round 2). Out-of-range numbers clamp
// to the model's range with a note and the effect is kept; an unmappable
// effect notes "(unreadable, not kept)" once; a bevel's gloss contour,
// contour and texture are noted; the bevel's angle turns clockwise and its
// altitude is the global one when `uglg` is set; seeded hostile descriptors
// read and render without a crash.
@testable import CoreRaster
import Foundation
import Testing

@Suite struct PSDEffectsClampTests {
    private func rgb(_ v: Double) -> Desc { .obj("RGBC", [("Rd  ", .doub(v)), ("Grn ", .doub(v)), ("Bl  ", .doub(v))]) }

    private func bevel(_ extra: [(String, Desc)]) -> Desc {
        .obj("ebbl", [("enab", .bool(true)), ("bvlS", .enm("BESl", "InrB")), ("hglC", rgb(255)), ("sdwC", rgb(0))] + extra)
    }

    @Test func outOfRangeValuesClampWithANoteAndKeepTheEffect() throws {
        let shadow = Desc.obj("DrSh", [("Clr ", rgb(0)), ("Opct", .untf("#Prc", 250)), ("uglg", .bool(false)),
                                       ("lagl", .untf("#Ang", 840)), ("Dstn", .untf("#Pxl", 1e9)),
                                       ("Ckmt", .untf("#Prc", 300)), ("blur", .untf("#Pxl", 5000))])
        let inner = Desc.obj("IrSh", [("Clr ", rgb(0)), ("Opct", .untf("#Prc", .nan)), ("Ckmt", .untf("#Prc", -5))])
        let stroke = Desc.obj("FrFX", [("Sz  ", .untf("#Pxl", 5000)), ("Clr ", rgb(0))])
        let bev = bevel([("uglg", .bool(false)), ("lagl", .untf("#Ang", 840)), ("Lald", .untf("#Ang", 120)), ("srgR", .untf("#Prc", 0)),
                         ("blur", .untf("#Pxl", 300)), ("Sftn", .untf("#Pxl", 99)), ("hglO", .untf("#Prc", -5))])
        let (layer, notes) = try readEffectsLayer(Desc.effects([("DrSh", shadow), ("IrSh", inner), ("FrFX", stroke), ("ebbl", bev)]).lfx2)
        guard let layer, let style = layer.style, style.entries.count == 4 else {
            Issue.record("not four entries: \(String(describing: layer?.style)) \(notes)"); return
        }
        let a = 120 * Double.pi / 180
        guard case let .dropShadow(_, dx, dy, spread, blur) = style.entries[0].op else { Issue.record("no drop shadow"); return }
        #expect(abs(dx + cos(a) * 30_000) < 1e-6 && abs(dy - sin(a) * 30_000) < 1e-6)
        #expect(spread == 1 && blur == 1_000 && style.entries[0].opacity == 1)
        guard case let .innerShadow(_, _, _, innerSpread, _) = style.entries[1].op else { Issue.record("no inner shadow"); return }
        #expect(innerSpread == 0 && style.entries[1].opacity == 1)
        #expect(style.entries[2].op == .stroke(fill: .color(RGBA(r: 0, g: 0, b: 0, a: 1)), width: 1_000, position: .outside))
        guard case let .bevel(b) = style.entries[3].op else { Issue.record("no bevel"); return }
        #expect(b.depth == 0.01 && b.size == 250 && b.soften == 16 && b.altitude == 90 && b.highlightOpacity == 0)
        #expect(abs(b.angle - 240) < 1e-9)
        let expected = ["drop shadow angle", "drop shadow distance", "drop shadow spread", "drop shadow size", "drop shadow opacity",
                        "inner shadow spread", "inner shadow opacity", "stroke width",
                        "bevel and emboss angle", "bevel and emboss depth", "bevel and emboss size", "bevel and emboss soften",
                        "bevel and emboss altitude", "bevel and emboss highlight opacity"].map { "L: \($0) (clamped)" }
        #expect(notes.sorted() == expected.sorted())
        #expect(try layer.pixels.styled(style).width == layer.pixels.width)
    }

    @Test func gradientScaleAndOffsetClamp() throws {
        let stops = Desc.list([.obj("Clrt", [("Clr ", rgb(0)), ("Lctn", .long(0))]), .obj("Clrt", [("Clr ", rgb(255)), ("Lctn", .long(4096))])])
        let gradient = Desc.obj("GrFl", [("Grad", .obj("Grdn", [("Clrs", stops)])), ("Angl", .untf("#Ang", 0)), ("Scl ", .untf("#Prc", 0)),
                                         ("Ofst", .obj("Pnt ", [("Hrzn", .untf("#Prc", 5000)), ("Vrtc", .untf("#Prc", 0))]))])
        let (layer, notes) = try readEffectsLayer(Desc.effects([("GrFl", gradient)]).lfx2)
        guard case let .overlay(.gradient(_, _, from, to))? = layer?.style?.entries.first?.op else {
            Issue.record("no gradient: \(notes)"); return
        }
        // 1% of the 8 px layer's half width either side of a centre 1000% of the width to the right.
        #expect(abs(from.x - (84 - 0.04)) < 1e-9 && abs(to.x - (84 + 0.04)) < 1e-9 && abs(from.y - 4) < 1e-9 && abs(to.y - 4) < 1e-9)
        #expect(notes == ["L: gradient overlay scale (clamped)", "L: gradient overlay offset (clamped)"])
    }

    @Test func anUnmappableEffectNotesOnceUnreadable() throws {
        let (layer, notes) = try readEffectsLayer(Desc.effects([("DrSh", .obj("DrSh", [("enab", .bool(true))]))]).lfx2)
        #expect(layer?.style?.entries.isEmpty == true)
        #expect(notes == ["L: drop shadow (unreadable, not kept)"])
    }

    @Test func bevelGlossContourContourAndTextureAreNoted() throws {
        let curve = Desc.obj("ShpC", [("Crv ", .list([.obj("CrPt", []), .obj("CrPt", []), .obj("CrPt", [])]))])
        let (layer, notes) = try readEffectsLayer(Desc.effects([("ebbl", bevel([("TrnS", curve), ("useShape", .bool(true)),
                                                                                 ("useTexture", .bool(true))]))]).lfx2)
        #expect(layer?.style?.entries.count == 1)
        #expect(notes == ["L: bevel and emboss gloss contour (not kept)", "L: bevel and emboss contour (not kept)",
                          "L: bevel and emboss texture (not kept)"])
        let (_, plain) = try readEffectsLayer(Desc.effects([("ebbl", bevel([("useShape", .bool(false)), ("useTexture", .bool(false))]))]).lfx2)
        #expect(plain.isEmpty)
    }

    /// The file's angle is counterclockwise; `Bevel.angle` turns clockwise, so 120 reads as 240.
    @Test func bevelAngleTurnsClockwiseAndUsesTheGlobalAltitude() throws {
        let own = bevel([("uglg", .bool(false)), ("lagl", .untf("#Ang", 120)), ("Lald", .untf("#Ang", 20))])
        let (ownLayer, _) = try readEffectsLayer(Desc.effects([("ebbl", own)]).lfx2, angle: 30, altitude: 45)
        guard case let .bevel(b)? = ownLayer?.style?.entries.first?.op else { Issue.record("no bevel"); return }
        #expect(abs(b.angle - 240) < 1e-9 && b.altitude == 20)
        let global = bevel([("uglg", .bool(true)), ("lagl", .untf("#Ang", 120)), ("Lald", .untf("#Ang", 20))])
        let (globalLayer, notes) = try readEffectsLayer(Desc.effects([("ebbl", global)]).lfx2, angle: 30, altitude: 45)
        guard case let .bevel(g)? = globalLayer?.style?.entries.first?.op else { Issue.record("no global bevel"); return }
        #expect(abs(g.angle - 330) < 1e-9 && g.altitude == 45 && notes.isEmpty)
        let (_, far) = try readEffectsLayer(Desc.effects([("ebbl", global)]).lfx2, angle: 30, altitude: 200)
        #expect(far == ["L: bevel and emboss altitude (clamped)"])
    }

    /// Seeded hostile numbers (NaN, infinities, huge, negative) in every effect and the global light:
    /// the file reads (or throws a `CodecError`) and its style renders through `styled`.
    @Test func hostileNumbersReadAndRender() throws {
        var rng = SplitMix64(seed: 0x15_C1A3)
        let picks: [Double] = [.nan, .infinity, -.infinity, 1e308, -1e308, -1, 0, 50, 300, 5_000, 2e9]
        let ints = [Int(Int32.min), -1, 0, 45, 400, Int(Int32.max)]
        var rendered = 0
        for _ in 0..<12 {
            func p() -> Desc { .untf("#Prc", picks[Int.random(in: 0..<picks.count, using: &rng)]) }
            let common: [(String, Desc)] = [("enab", .bool(true)), ("Opct", p()), ("uglg", .bool(Bool.random(using: &rng))), ("lagl", p())]
            let shadow = Desc.obj("DrSh", common + [("Clr ", rgb(300)), ("Dstn", p()), ("Ckmt", p()), ("blur", p())])
            let glow = Desc.obj("IrGl", common + [("Clr ", rgb(-1)), ("Ckmt", p()), ("blur", p())])
            let stroke = Desc.obj("FrFX", common + [("Styl", .enm("FStl", "CtrF")), ("Sz  ", p()), ("Clr ", rgb(0))])
            let stops = Desc.list([.obj("Clrt", [("Clr ", rgb(0)), ("Lctn", .long(0))]), .obj("Clrt", [("Clr ", rgb(255)), ("Lctn", .long(4096))])])
            let gradient = Desc.obj("GrFl", common + [("Grad", .obj("Grdn", [("Clrs", stops), ("Trns", .list([.obj("TrnS", [("Opct", p())])]))])),
                                                      ("Angl", p()), ("Scl ", p()), ("Ofst", .obj("Pnt ", [("Hrzn", p()), ("Vrtc", p())]))])
            let bev = bevel(common + [("blur", p()), ("srgR", p()), ("Sftn", p()),
                                      ("Lald", p()), ("hglO", p()), ("sdwO", p())])
            let fx = Desc.effects([("DrSh", shadow), ("IrGl", glow), ("FrFX", stroke), ("GrFl", gradient), ("ebbl", bev)])
            let angle = ints[Int.random(in: 0..<ints.count, using: &rng)], altitude = ints[Int.random(in: 0..<ints.count, using: &rng)]
            let layer: PixelLayer?
            do { (layer, _) = try readEffectsLayer(fx.lfx2, angle: angle, altitude: altitude) } catch is CodecError { continue }
            guard let layer, let style = layer.style else { Issue.record("no style"); continue }
            #expect(style.entries.count == 5)
            #expect(throws: Never.self) { _ = try layer.pixels.styled(style) }
            rendered += 1
        }
        #expect(rendered == 12)
    }
}
