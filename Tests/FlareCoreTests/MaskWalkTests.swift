// MaskWalkTests.swift: KJ-MM's vector half (MM-9; the raster half is
// CoreRenderTests' MaskWalkTests, so the filter `MaskWalkTests.walk` runs both).
// Fixtures/mask-walk.flare holds a gradient layer with one hard mask under a
// hidden text layer. A luma matte from the text onto the gradient is set by
// command, undone and redone; the file round-trips with it; the render list
// names the matte and the mask; SVG writes the mask's clipPath and a
// luminance mask holding the text; Lottie writes masksProperties and `tt: 3`
// with `td: 1` directly above. Lottie text is not written yet (the exporter
// throws `unsupported("text")`, checked here), so the Lottie step swaps the
// text for a box over its glyphs.
import Foundation
@testable import FlareCore
import Testing

@Suite struct MaskWalkTests {
    static let owner = LayerOwner.scene("walk")
    static let luma = TrackMatte(sourceLayerID: "title", kind: .luma)

    static func fixture() throws -> Document {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/mask-walk.flare")
        return try FlareFormat.decode(Data(contentsOf: url))
    }

    @Test func walk() throws {
        // 1. The matte by command, undone and redone exactly.
        let start = try Self.fixture()
        var engine = CommandEngine(document: start)
        try engine.perform(SetTrackMatte(owner: Self.owner, layerID: "sky", matte: Self.luma))
        let matted = engine.document
        #expect(matted.scenes.first?.layers.map(\.matte) == [Self.luma, nil])
        try engine.undo()
        #expect(engine.document == start)
        try engine.redo()
        #expect(engine.document == matted)
        #expect(try FlareFormat.decode(FlareFormat.encode(matted)) == matted)
        let scene = try #require(matted.scenes.first)

        // 2. The render list: the sky item carries its mask and names the
        // hidden text as its luma matte, listed only as a matte.
        let list = scene.renderList(at: 0, symbols: matted.symbols)
        #expect(list.items.map(\.address.layerID) == ["sky"])
        let sky = try #require(list.items.first)
        #expect(sky.matte == MatteLink(sourceItems: 0..<1, inMatteItems: true, kind: .luma))
        #expect(sky.clips.map(\.path) == scene.layers[0].masks.map(\.path) && sky.clips.map(\.mode) == [.add])
        #expect(list.matteItems.map(\.address.layerID) == ["title"])
        #expect(list.matteItems.map(\.isMatteSource) == [true] && list.matteItems.map(\.isText) == [true])

        // 3. SVG: the mask is a clipPath on the sky's group, wrapped by a
        // luminance mask that holds the text and no id of its own.
        let svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(svg.contains("<path d=\"M10 10 L190 10 L190 90 L10 90 Z\"/>\n</clipPath>"))
        let open = try #require(svg.range(of: "mask-type=\"luminance\""))
        let close = try #require(svg.range(of: "</mask>", range: open.upperBound..<svg.endIndex))
        let held = svg[open.upperBound..<close.lowerBound]
        #expect(held.contains("data-id=\"title\"") && held.contains("MASK"))
        #expect(svg.contains("<g mask=\"url(#") && svg.contains("<g id=\"sky\"") && !svg.contains(" id=\"title\""))
        #expect(svg.contains("clip-path=\"url(#") && svg.contains("<linearGradient"))
        #expect(try SVGExporter.export(scene: scene, frame: 0) == svg)

        // 4. Lottie: the text source throws until Lottie text is written; with
        // a box over the glyphs in its place, `td: 1` sits directly above the
        // sky's `tt: 3`, and the sky carries its mask.
        #expect(throws: LottieExportError.unsupported("text")) { try LottieExporter.export(scene: scene) }
        var boxed = scene
        boxed.layers[1].texts = []
        boxed.layers[1].shapes = [Shape(points: [Point(x: 30, y: 30), Point(x: 170, y: 30), Point(x: 170, y: 70),
                                                 Point(x: 30, y: 70)], fill: .solid(Color(r: 1, g: 1, b: 1, a: 1)))]
        let layers = try LottieMaskExportTests.layers(boxed)
        #expect(layers.map { $0["nm"] as? String } == ["Title", "Sky"])
        #expect(layers.map { $0["td"] as? Int } == [1, nil] && layers.map { $0["tt"] as? Int } == [nil, 3])
        let masks = try #require(layers.last?["masksProperties"] as? [[String: Any]])
        #expect(masks.map { $0["mode"] as? String } == ["a"] && layers.last?["hasMask"] as? Bool == true)
    }
}
