// PSDEffectsTests.swift: layer styles read from PSD files (layer-style-engine
// LE-1, LE-6). A test-written `lfx2` block (descriptor bytes from the published
// spec) reads into `PixelLayer.style`; what the stack cannot hold becomes a
// note; damaged effect bytes note "unreadable" and the layer still opens.
@testable import CoreRaster
import Foundation
import Testing

/// Effect descriptors for the tests below; `Desc` is in PSDDescriptorTests.swift.
private extension Desc {
    /// An `lfx2` tagged block holding this descriptor.
    var lfx2: [UInt8] {
        var w = BigEndian(); w.ascii("8BIMlfx2")
        w.sized(pad: 2) { b in b.u32(0); b.u32(16); write(&b) }
        return w.out
    }

    static func shadow(opacity: Double = 75, globalLight: Bool = true) -> Desc {
        .obj("DrSh", [("enab", .bool(true)), ("Md  ", .enm("BlnM", "Mltp")), ("Clr ", .obj("RGBC", [("Rd  ", .doub(255)), ("Grn ", .doub(0)), ("Bl  ", .doub(0))])),
                      ("Opct", .untf("#Prc", opacity)), ("uglg", .bool(globalLight)), ("lagl", .untf("#Ang", 120)),
                      ("Dstn", .untf("#Pxl", 10)), ("Ckmt", .untf("#Pxl", 20)), ("blur", .untf("#Pxl", 5))])
    }
    static let stroke = Desc.obj("FrFX", [("Styl", .enm("FStl", "InsF")), ("PntT", .enm("FrFl", "SClr")), ("Md  ", .enm("BlnM", "Nrml")),
                                          ("Opct", .untf("#Prc", 100)), ("Sz  ", .untf("#Pxl", 3)),
                                          ("Clr ", .obj("RGBC", [("Rd  ", .doub(0)), ("Grn ", .doub(0)), ("Bl  ", .doub(255))]))])
    static func effects(_ items: [(String, Desc)], master: Bool = true) -> Desc {
        .obj("null", [("Scl ", .untf("#Prc", 100)), ("masterFXSwitch", .bool(master))] + items)
    }
}

@Suite struct PSDEffectsTests {
    private func oneLayer() throws -> LayeredImage {
        let layer = PixelLayer(name: "badge", pixels: try StyleFixtures.badge())
        return LayeredImage(width: 48, height: 32, nodes: [.pixels(layer)])
    }

    /// One 8 x 8 layer named "L" carrying `extra`, under a global light of 30 degrees.
    private func read(_ extra: [UInt8]) throws -> (LayerStyleStack?, [String]) {
        var record = PSDRecord.layer("L", top: 0, left: 0, height: 8, width: 8)
        record.extra = extra
        var light = BigEndian(); light.ascii("8BIM"); light.u16(1037); light.u16(0); light.sized { $0.u32(30) }
        let image = try PSD.read(PSDFile(width: 16, height: 16, records: [record], resources: light.out).data)
        return (pixelLayer(image.nodes.first)?.style, image.notes)
    }

    @Test func usesGlobalLight() throws {
        let (style, notes) = try read(Desc.effects([("DrSh", .shadow()), ("FrFX", .stroke)]).lfx2)
        #expect(notes.isEmpty)
        let a = 30 * Double.pi / 180
        guard let entries = style?.entries, entries.count == 2, case let .dropShadow(color, dx, dy, spread, blur) = entries[0].op else {
            Issue.record("no drop shadow: \(String(describing: style))"); return
        }
        #expect(abs(dx + cos(a) * 10) < 1e-9 && abs(dy - sin(a) * 10) < 1e-9)
        #expect(spread == 0.2 && blur == 5 && color == RGBA(r: 1, g: 0, b: 0, a: 1))
        #expect(entries[0].mode == .multiply && entries[0].isEnabled)
        #expect(entries[1].op == .stroke(fill: .color(RGBA(r: 0, g: 0, b: 1, a: 1)), width: 3, position: .inside))
        let (own, _) = try read(Desc.effects([("DrSh", .shadow(globalLight: false))]).lfx2)
        guard case let .dropShadow(_, ownX, _, _, _)? = own?.entries.first?.op else { Issue.record("no own-angle shadow"); return }
        #expect(abs(ownX + cos(120 * Double.pi / 180) * 10) < 1e-9)
    }

    @Test func opacityIsPercent() throws {
        let (style, _) = try read(Desc.effects([("DrSh", .shadow(opacity: 50))]).lfx2)
        #expect(style?.entries.first?.opacity == 0.5)
        #expect(style?.fillOpacity == 1)
    }

    @Test func masterSwitchOffDisablesEveryEntry() throws {
        let (style, _) = try read(Desc.effects([("DrSh", .shadow()), ("FrFX", .stroke)], master: false).lfx2)
        #expect(style?.entries.count == 2)
        #expect(style?.entries.allSatisfy { !$0.isEnabled } == true)
    }

    @Test func multiNoted() throws {
        let effects = Desc.effects([("DrSh", .shadow()), ("dropShadowMulti", .list([.shadow(), .shadow(opacity: 20)])),
                                    ("ChFX", .obj("ChFX", [("enab", .bool(true))]))])
        let (style, notes) = try read(effects.lfx2)
        #expect(style?.entries.count == 1)
        #expect(notes == ["L: drop shadow 2 (not kept)", "L: satin (not kept)"])
    }

    @Test func zerosNoteUnreadableAndTheLayerStillOpens() throws {
        var w = BigEndian(); w.ascii("8BIMlfx2"); w.sized { $0.out += Array(repeating: 0, count: 16) }
        let (style, notes) = try read(w.out)
        #expect(style == nil)
        #expect(notes == ["L: layer effects (unreadable, not kept)"])
    }

    @Test func aFileWithoutEffectsReadsNoStyleAndNoNotes() throws {
        #expect(try oneLayer().notes.isEmpty)
        let written = try PSD.write(oneLayer()), read = try PSD.read(written)
        #expect(read.notes.isEmpty)
        #expect(try PSD.write(read) == written)
        #expect(pixelLayer(read.nodes.first)?.style == nil)
        let fixture = try PSD.read(loadCodecFixture("layers.psd"))
        #expect(fixture.notes.isEmpty)
    }

    @Test func randomAndTruncatedEffectsNoteUnreadable() throws {
        var rng = SplitMix64(seed: 0x1F_C0DE)
        let valid = Desc.effects([("DrSh", .shadow()), ("FrFX", .stroke)]).bytes
        for round in 0..<400 {
            var bytes = Array(valid.prefix(Int.random(in: 0..<valid.count, using: &rng)))
            if round % 2 == 0 {
                bytes = (0..<Int.random(in: 0..<256, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
                if round % 4 == 0 { bytes = Array(valid.prefix(40)) + bytes }
            }
            var block = BigEndian(); block.u32(0); block.u32(16); block.out += bytes
            let (style, notes) = PSDEffects.style(ByteReader(Data(block.out)), fill: 255, oldBlock: false, layer: "L",
                                                  width: 8, height: 8, light: PSDGlobalLight())
            #expect(style == nil && notes == ["L: layer effects (unreadable, not kept)"])
        }
    }
}
