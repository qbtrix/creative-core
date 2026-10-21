// BlendModeTests.swift: linear dodge and linear burn (layer-style-engine LE-7). Their formulas,
// min(1, Cb + Cs) and max(0, Cb + Cs - 1), clamp at both ends; the PSD keys `lddg` and `lbrn`
// read as the two modes and write back as themselves; an unknown PSD key opens as Normal with a
// note naming it; OpenRaster's `svg:plus` and `afterglow:linear-burn` round-trip.
import CoreRaster
import Foundation
import Testing

@Suite struct BlendModeTests {
    /// Opaque `source` over opaque `backdrop`, one grey channel each: B(Cb, Cs) itself.
    private func blended(_ mode: BlendMode, _ backdrop: Float, _ source: Float) throws -> Float {
        let s = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: source, g: source, b: source, a: 1))
        let b = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: backdrop, g: backdrop, b: backdrop, a: 1))
        return try composite(s, onto: b, mode: mode, opacity: 1).pixel(x: 0, y: 0).r
    }

    /// One 8 x 8 layer named "L" with blend key `key`, read back.
    private func read(key: String) throws -> (PixelLayer?, [String]) {
        var record = PSDRecord.layer("L", top: 0, left: 0, height: 8, width: 8)
        record.blendKey = key
        let image = try PSD.read(PSDFile(width: 16, height: 16, records: [record]).data)
        return (pixelLayer(image.nodes.first), image.notes)
    }

    /// A linear dodge layer under a linear burn one, for the writers.
    private func bothModes() throws -> LayeredImage {
        let layers = try [BlendMode.linearDodge, .linearBurn].enumerated().map { i, mode in
            LayerNode.pixels(PixelLayer(name: mode.rawValue, pixels: try ORAFixtures.pixels(UInt64(i), 2, 2), blendMode: mode))
        }
        return LayeredImage(width: 4, height: 4, nodes: layers, composite: try ORAFixtures.pixels(9, 4, 4))
    }

    private func modes(_ image: LayeredImage) -> [BlendMode?] { image.nodes.map { pixelLayer($0)?.blendMode } }

    @Test func linearDodgeClampsAtOne() throws {
        #expect(try blended(.linearDodge, 0.6, 0.6) == 1)
        #expect(abs(try blended(.linearDodge, 0.25, 0.5) - 0.75) <= 1e-6)
        #expect(try blended(.linearDodge, 0, 0) == 0)
    }

    @Test func linearBurnFloor() throws {
        #expect(try blended(.linearBurn, 0.2, 0.2) == 0)
        #expect(abs(try blended(.linearBurn, 0.75, 0.5) - 0.25) <= 1e-6)
        #expect(try blended(.linearBurn, 1, 1) == 1)
    }

    @Test func keysMapApart() throws {
        let (dodge, dodgeNotes) = try read(key: "lddg")
        let (burn, burnNotes) = try read(key: "lbrn")
        #expect(dodge?.blendMode == .linearDodge && burn?.blendMode == .linearBurn)
        #expect(dodgeNotes.isEmpty && burnNotes.isEmpty)
        #expect(modes(try PSD.read(try PSD.write(try bothModes()))) == [.linearDodge, .linearBurn])
    }

    /// A drop shadow in `mode`, read from an `lfx2` block (`Desc` is in PSDDescriptorTests.swift).
    @Test func effectDescriptorsKeepBoth() throws {
        for (value, mode) in [("linearDodge", BlendMode.linearDodge), ("linearBurn", .linearBurn)] {
            let shadow = Desc.obj("DrSh", [("enab", .bool(true)), ("Md  ", .enm("BlnM", value)),
                                           ("Clr ", .obj("RGBC", [("Rd  ", .doub(255)), ("Grn ", .doub(0)), ("Bl  ", .doub(0))])),
                                           ("Opct", .untf("#Prc", 75)), ("uglg", .bool(false)), ("lagl", .untf("#Ang", 120)),
                                           ("Dstn", .untf("#Pxl", 10)), ("Ckmt", .untf("#Pxl", 20)), ("blur", .untf("#Pxl", 5))])
            var block = BigEndian(); block.ascii("8BIMlfx2")
            block.sized(pad: 2) { b in b.u32(0); b.u32(16); Desc.obj("null", [("DrSh", shadow)]).write(&b) }
            var record = PSDRecord.layer("L", top: 0, left: 0, height: 8, width: 8)
            record.extra = block.out
            let image = try PSD.read(PSDFile(width: 16, height: 16, records: [record]).data)
            #expect(pixelLayer(image.nodes.first)?.style?.entries.first?.mode == mode, "\(value)")
            #expect(!image.notes.contains { $0.contains(value) }, "\(image.notes)")
        }
    }

    @Test func unknownKeyNotesItsName() throws {
        let (layer, notes) = try read(key: "zzzz")
        #expect(layer?.blendMode == .normal)
        #expect(notes == ["L: blend mode zzzz (not kept)"])
        let (_, known) = try read(key: "mul ")
        #expect(known.isEmpty)
    }

    @Test func openRasterKeepsBoth() throws {
        let written = try OpenRaster.write(try bothModes(), pixels: RawPixelCodec())
        #expect(modes(try OpenRaster.read(written, pixels: RawPixelCodec())) == [.linearDodge, .linearBurn])
        let stack = String(decoding: try #require(try ZipStore.entries(written)["stack.xml"]), as: UTF8.self)
        #expect(stack.contains("composite-op=\"svg:plus\"") && stack.contains("composite-op=\"afterglow:linear-burn\""))
    }
}
