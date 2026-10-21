// PSDEffectsMappingTests.swift: each PSD effect field reads into its exact
// style op (layer-style-engine LE-6, Anatomy round 2): glow kinds, stroke
// position and paint, gradient reverse, opacity stops, shape, offset and
// scale, bevel style, technique, direction, depth and soften, `enab`; the
// layer's `iOpa` as fill opacity; every part the stack cannot hold, and
// every malformed list, key or resource, adds a note instead of vanishing;
// the global light walker passes odd and named resources and never traps.
@testable import CoreRaster
import Foundation
import Testing

@Suite struct PSDEffectsMappingTests {
    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Desc { .obj("RGBC", [("Rd  ", .doub(r)), ("Grn ", .doub(g)), ("Bl  ", .doub(b))]) }

    /// The one entry `effect` (stored under `key`) reads as, and the notes.
    private func entry(_ key: String, _ effect: Desc) throws -> (StyleEntry?, [String]) {
        let (layer, notes) = try readEffectsLayer(Desc.effects([(key, effect)]).lfx2)
        return (layer?.style?.entries.count == 1 ? layer?.style?.entries.first : nil, notes)
    }

    private func bevel(_ extra: [(String, Desc)]) -> Desc {
        .obj("ebbl", [("hglC", rgb(255, 255, 255)), ("sdwC", rgb(0, 0, 0)), ("blur", .untf("#Pxl", 10))] + extra)
    }

    private var stops: Desc {
        .list([.obj("Clrt", [("Clr ", rgb(0, 0, 0)), ("Lctn", .long(0))]), .obj("Clrt", [("Clr ", rgb(255, 255, 255)), ("Lctn", .long(4096))])])
    }

    @Test func everyFieldMapsToItsOp() throws {
        let white = RGBA(r: 1, g: 1, b: 1, a: 1), red = RGBA(r: 1, g: 0, b: 0, a: 1)
        let glow = try entry("IrGl", .obj("IrGl", [("Clr ", rgb(255, 255, 255)), ("Md  ", .enm("BlnM", "Scrn")), ("Opct", .untf("#Prc", 80)),
                                                   ("Ckmt", .untf("#Prc", 10)), ("blur", .untf("#Pxl", 4))]))
        #expect(glow.0?.op == .innerGlow(color: white, spread: 0.1, size: 4) && glow.0?.mode == .screen && glow.0?.opacity == 0.8)
        #expect(try entry("SoFi", .obj("SoFi", [("Clr ", rgb(255, 0, 0))])).0?.op == .overlay(.color(red)))
        for (styl, position) in [("CtrF", StrokePosition.center), ("OutF", .outside), ("InsF", .inside)] {
            let stroke = try entry("FrFX", .obj("FrFX", [("Styl", .enm("FStl", styl)), ("Sz  ", .untf("#Pxl", 2)), ("Clr ", rgb(255, 0, 0))]))
            #expect(stroke.0?.op == .stroke(fill: .color(red), width: 2, position: position))
        }
        let painted = try entry("FrFX", .obj("FrFX", [("PntT", .enm("FrFl", "GrFl")), ("Sz  ", .untf("#Pxl", 2)),
                                                      ("Grad", .obj("Grdn", [("Clrs", stops)]))]))
        guard case .stroke(fill: .gradient, width: 2, position: .outside)? = painted.0?.op else { Issue.record("no gradient stroke: \(painted)"); return }
        let trns = Desc.list([.obj("TrnS", [("Opct", .untf("#Prc", 100)), ("Lctn", .long(0))]), .obj("TrnS", [("Opct", .untf("#Prc", 0)), ("Lctn", .long(4096))])])
        let gradient = try entry("GrFl", .obj("GrFl", [("Grad", .obj("Grdn", [("Clrs", stops), ("Trns", trns)])), ("Rvrs", .bool(true)),
                                                       ("Type", .enm("GrdT", "Rdl ")), ("Angl", .untf("#Ang", 0)), ("Scl ", .untf("#Prc", 50)),
                                                       ("Ofst", .obj("Pnt ", [("Hrzn", .untf("#Prc", 10)), ("Vrtc", .untf("#Prc", -10))]))]))
        guard case let .overlay(.gradient(gStops, shape, from, to))? = gradient.0?.op else { Issue.record("no gradient: \(gradient)"); return }
        // Reversed: white (alpha 0 from the opacity stops) at 0, black (alpha 1) at 1.
        #expect(gStops == [RasterGradientStop(offset: 0, color: RGBA(r: 1, g: 1, b: 1, a: 0)), RasterGradientStop(offset: 1, color: RGBA(r: 0, g: 0, b: 0, a: 1))])
        // Radial from the centre moved 10% right and up of 8 px, out half the 50%-scaled width.
        #expect(shape == .radial && abs(from.x - 4.8) < 1e-9 && abs(from.y - 3.2) < 1e-9 && abs(to.x - 6.8) < 1e-9 && abs(to.y - 3.2) < 1e-9)
        let rows: [([(String, Desc)], BevelShape, BevelTechnique, Bool)] = [
            ([("bvlS", .enm("BESl", "OtrB")), ("bvlT", .enm("bvlT", "PrBL")), ("bvlD", .enm("BESs", "Out ")), ("srgR", .untf("#Prc", 250)),
              ("Sftn", .untf("#Pxl", 3))], .outerBevel, .chiselHard, false),
            ([("bvlS", .enm("BESl", "Embs")), ("bvlT", .enm("bvlT", "Slmt"))], .emboss, .chiselSoft, true),
            ([("bvlS", .enm("BESl", "PlEb"))], .pillowEmboss, .smooth, true)]
        for (fields, shape, technique, up) in rows {
            guard case let .bevel(b)? = try entry("ebbl", bevel(fields)).0?.op else { Issue.record("no bevel: \(fields)"); continue }
            #expect(b.shape == shape && b.technique == technique && b.up == up)
            if shape == .outerBevel { #expect(b.depth == 2.5 && b.soften == 3) }
        }
        let off = try entry("DrSh", .obj("DrSh", [("enab", .bool(false)), ("Clr ", rgb(0, 0, 0))]))
        #expect(off.0?.isEnabled == false)
    }

    private func iOpa(_ value: UInt8) -> [UInt8] {
        var w = BigEndian(); w.ascii("8BIMiOpa"); w.sized { $0.out += [value, 0, 0, 0] }
        return w.out
    }

    @Test func fillOpacityFromIOpa() throws {
        let (shadowed, _) = try readEffectsLayer(iOpa(128) + Desc.effects([("DrSh", .shadow())]).lfx2)
        #expect(shadowed?.style?.fillOpacity == Float(128) / 255 && shadowed?.style?.entries.count == 1)
        let (bare, notes) = try readEffectsLayer(iOpa(0))
        #expect(bare?.style == LayerStyleStack(entries: [], fillOpacity: 0) && notes.isEmpty)
    }

    @Test func everyDroppedPartIsNoted() throws {
        var old = BigEndian(); old.ascii("8BIMlrFX"); old.sized { $0.out += [0, 0, 0, 0] }
        let (layer, lrFX) = try readEffectsLayer(old.out)
        #expect(layer?.style == nil && lrFX == ["L: layer effects in the older lrFX block (not kept)"])
        let curve = Desc.obj("ShpC", [("Crv ", .list([.obj("CrPt", []), .obj("CrPt", []), .obj("CrPt", [])]))])
        let cases: [(String, Desc, String)] = [
            ("patternFill", .obj("patternFill", [("enab", .bool(true))]), "pattern overlay (not kept)"),
            ("DrSh", .obj("DrSh", [("Clr ", rgb(0, 0, 0)), ("TrnS", curve)]), "drop shadow contour (not kept)"),
            ("FrFX", .obj("FrFX", [("PntT", .enm("FrFl", "Ptrn")), ("Sz  ", .untf("#Pxl", 2))]), "stroke (unreadable, not kept)"),
            ("DrSh", .obj("DrSh", [("Clr ", rgb(0, 0, 0)), ("Md  ", .enm("BlnM", "Zzzz"))]), "drop shadow blend mode Zzzz (not kept)")]
        for (key, effect, note) in cases {
            #expect(try readEffectsLayer(Desc.effects([(key, effect)]).lfx2).1 == ["L: \(note)"])
        }
        #expect(try groupNotes(Desc.effects([("DrSh", .shadow())]).lfx2) == ["G: layer effects (not kept)"])
    }

    /// The notes of a file holding one layer inside a group "G" whose folder record carries `extra`.
    private func groupNotes(_ extra: [UInt8]) throws -> [String] {
        var folder = PSDRecord.folder("G")
        folder.extra = extra
        return try PSD.read(PSDFile(width: 16, height: 16, records: [.divider, .layer("A", top: 0, left: 0, height: 4, width: 4), folder]).data).notes
    }

    @Test func groupFillOpacityIsNoted() throws {
        #expect(try groupNotes(iOpa(0)) == ["G: fill opacity (not kept)"])
        #expect(try groupNotes(iOpa(255)).isEmpty)
    }

    @Test func malformedMultiIsNoted() throws {
        // A list that is not a list: the single DrSh is still read and the lost list is noted.
        let notAList = try readEffectsLayer(Desc.effects([("DrSh", .shadow()), ("dropShadowMulti", .shadow())]).lfx2)
        #expect(notAList.0?.style?.entries.count == 1 && notAList.1 == ["L: drop shadow list (unreadable, not kept)"])
        let badItem = try readEffectsLayer(Desc.effects([("DrSh", .shadow()), ("dropShadowMulti", .list([.long(1)]))]).lfx2)
        #expect(badItem.0?.style?.entries.isEmpty == true && badItem.1 == ["L: drop shadow (unreadable, not kept)"])
        let notAnObject = try readEffectsLayer(Desc.effects([("ebbl", .list([bevel([])])), ("ChFX", .long(1))]).lfx2)
        #expect(notAnObject.1 == ["L: bevel and emboss (unreadable, not kept)", "L: satin (not kept)"])
    }

    @Test func glowSettingsTheStackCannotHoldAreNoted() throws {
        let glow = Desc.obj("IrGl", [("enab", .bool(true)), ("Md  ", .enm("BlnM", "Scrn")), ("Clr ", rgb(255, 255, 190)),
                                     ("Opct", .untf("#Prc", 75)), ("glwS", .enm("IGSr", "SrcC")), ("Nose", .untf("#Prc", 10)),
                                     ("ShdN", .untf("#Prc", 5)), ("GlwT", .enm("BETE", "PrBL")), ("Inpr", .untf("#Prc", 40)),
                                     ("Grad", .obj("Grdn", [("Clrs", stops)])), ("Ckmt", .untf("#Pxl", 0)), ("blur", .untf("#Pxl", 5))])
        let (layer, notes) = try readEffectsLayer(Desc.effects([("IrGl", glow)]).lfx2)
        #expect(layer?.style?.entries.count == 1)
        #expect(notes == ["noise", "source centre", "jitter", "precise technique", "range", "gradient"].map { "L: inner glow \($0) (not kept)" })
        let defaults = Desc.obj("IrGl", [("Clr ", rgb(255, 255, 255)), ("glwS", .enm("IGSr", "SrcE")), ("Nose", .untf("#Prc", 0)),
                                         ("ShdN", .untf("#Prc", 0)), ("GlwT", .enm("BETE", "SfBL")), ("Inpr", .untf("#Prc", 50))])
        #expect(try readEffectsLayer(Desc.effects([("IrGl", defaults)]).lfx2).1.isEmpty)
        let shadow = Desc.obj("DrSh", [("Clr ", rgb(0, 0, 0)), ("layerConceals", .bool(false))])
        #expect(try readEffectsLayer(Desc.effects([("DrSh", shadow)]).lfx2).1 == ["L: drop shadow knock-out off (not kept)"])
    }

    /// A resource: `8BIM`, `id`, a Pascal name padded to even, then `data` padded to even.
    private func resource(_ id: Int, name: String = "", _ data: [UInt8]) -> [UInt8] {
        var w = BigEndian(); w.ascii("8BIM"); w.u16(id)
        let n = Array(name.utf8)
        w.out += [UInt8(n.count)] + n + (n.count % 2 == 0 ? [0] : [])
        w.u32(data.count); w.out += data + (data.count % 2 == 1 ? [0] : [])
        return w.out
    }

    private func i32(_ v: Int) -> [UInt8] { var w = BigEndian(); w.u32(v); return w.out }

    @Test func globalLightSkipsOddAndNamedResources() throws {
        let bytes = resource(1000, name: "ab", [1, 2, 3]) + resource(1037, name: "x", i32(45)) + resource(1049, i32(20))
        let light = try PSDGlobalLight(resources: ByteReader(bytes))
        #expect(light.angle == 45 && light.altitude == 20 && !light.damaged)
    }

    @Test func damagedGlobalLightIsNoted() throws {
        let short = PSDFile(width: 16, height: 16, resources: resource(1037, [0, 45]) + resource(1049, i32(20)))
        #expect(try PSD.read(short.data).notes == ["global light (unreadable, default used)"])
        // A section cut inside a resource throws rather than dropping the light in silence.
        let cut = PSDFile(width: 16, height: 16, resources: Array(resource(1037, i32(45)).prefix(9)))
        #expect(throws: CodecError.self) { _ = try PSD.read(cut.data) }
    }

    @Test func globalLightFuzz() {
        var rng = SplitMix64(seed: 0x61_0B41)
        let valid = resource(1000, name: "ab", [1, 2, 3]) + resource(1037, i32(45)) + resource(1049, i32(20))
        for round in 0..<500 {
            var bytes = Array(valid.prefix(Int.random(in: 0...valid.count, using: &rng)))
            if round % 2 == 0 {
                bytes = (0..<Int.random(in: 0..<64, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
                if round % 4 == 0 { bytes = Array(valid.prefix(14)) + bytes }
            }
            do { _ = try PSDGlobalLight(resources: ByteReader(bytes)) } catch is CodecError {} catch {
                Issue.record("not a CodecError: \(error)")
            }
        }
    }
}
