// SVGMaskExportTests.swift: MM-8 acceptance for SVG layer masks (clipPath, mask,
// blur of feather / 3, difference by difference blend) and track mattes (mask
// holding the source), and refusals.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import FlareCore
import Testing

@Suite struct SVGMaskExportTests {
    static let region = " x=\"-100000\" y=\"-100000\" width=\"200000\" height=\"200000\""

    static func scene() throws -> Scene { try #require(MatteRenderListTests.fixture().scenes.first) }

    @Test func fixtureWritesClipMaskAndMatte() throws {
        let svg = try SVGExporter.export(scene: Self.scene(), frame: 0)
        #expect(svg.contains("""
            <clipPath id="c0">
            <path d="M10 10 L90 10 L90 90 L10 90 Z"/>
            </clipPath>
            <filter id="f1" filterUnits="userSpaceOnUse" x="22" y="22" width="56" height="56">
            <feGaussianBlur stdDeviation="2.6667"/>
            </filter>
            <mask id="m2" maskUnits="userSpaceOnUse"\(Self.region)>
            <rect\(Self.region) fill="#fff"/>
            <path d="M50 30 L70 50 L50 70 L30 50 Z" fill="#000" fill-opacity="0.75" filter="url(#f1)"/>
            </mask>
            <g id="card" data-name="Card" transform="matrix(1 0 0 1 0 0)" clip-path="url(#c0)" mask="url(#m2)">
            """))
        #expect(svg.contains("""
            <mask id="m3" mask-type="luminance" maskUnits="userSpaceOnUse"\(Self.region)>
            <g data-id="lumen" data-name="Lumen" transform="matrix(1 0 0 1 0 0)">
            <path d="M20 20 L80 20 L80 80 L20 80 Z" fill="#808080"/>
            </g>
            </mask>
            <g mask="url(#m3)">
            <g id="photo" data-name="Photo" transform="matrix(1 0 0 1 0 0)">
            """))
        #expect(svg.components(separatedBy: "<clipPath").count == 2 && svg.components(separatedBy: "<mask").count == 3)
        #expect(!svg.contains(" id=\"lumen\""))
        #expect(try SVGExporter.export(scene: Self.scene(), frame: 0) == svg)
    }

    /// Feather is the blur radius, sigma = feather / 3, as `Mask.feathered(radius:)` takes it; the box widens by the feather.
    @Test func blurIsAThirdOfFeather() throws {
        var scene = try Self.scene()
        scene.layers[0].masks[1].feather = 6
        let svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(svg.contains("<feGaussianBlur stdDeviation=\"2\"/>"))
        #expect(svg.contains("x=\"24\" y=\"24\" width=\"52\" height=\"52\""))
    }

    /// Masks that are not a hard add run followed by removals all paint one mask, starting full or empty.
    @Test func paintedMasksStartByFirstMode() throws {
        var scene = try Self.scene()
        scene.layers[0].masks[1].mode = .add
        var svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(!svg.contains("<clipPath") && !svg.contains("<rect\(Self.region) fill=\"#fff\"/>"))
        #expect(svg.contains("<path d=\"M10 10 L90 10 L90 90 L10 90 Z\" fill=\"#fff\"/>"))
        scene.layers[0].masks = [LayerMask(path: MatteRenderListTests.square(10, 90), mode: .intersect, inverted: true)]
        svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(svg.contains("<rect\(Self.region) fill=\"#fff\"/>\n<path d=\"M10 10 L90 10 L90 90 L10 90 Z\" fill=\"#000\"/>"))
        scene.layers[0].masks[0].inverted = false
        svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(svg.contains("fill=\"#000\" fill-rule=\"evenodd\"/>"))
    }

    @Test func invertedMatteKinds() throws {
        var scene = try Self.scene()
        scene.layers[1].matte?.kind = .lumaInverted
        var svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(svg.contains("<rect\(Self.region) fill=\"#fff\"/>\n<g style=\"mix-blend-mode:difference\">\n<g data-id=\"lumen\""))
        scene.layers[1].matte?.kind = .alphaInverted
        svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(svg.contains("<feColorMatrix type=\"matrix\" values=\"0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0\"/>"))
        #expect(svg.contains("<rect\(Self.region) fill=\"#fff\"/>\n<g filter=\"url(#f3)\">\n<g data-id=\"lumen\""))
        scene.layers[1].matte?.kind = .alpha
        svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(svg.contains("<mask id=\"m3\" mask-type=\"alpha\""))
    }

    /// Difference toggles: a white path blended by difference inside the mask, and it keeps a hard add run from clipping.
    @Test func differenceToggles() throws {
        var scene = try Self.scene()
        scene.layers[0].masks[1].mode = .difference
        let svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(!svg.contains("<clipPath"))
        #expect(svg.contains("""
            <mask id="m1" maskUnits="userSpaceOnUse"\(Self.region)>
            <path d="M10 10 L90 10 L90 90 L10 90 Z" fill="#fff"/>
            <path d="M50 30 L70 50 L50 70 L30 50 Z" fill="#fff" fill-opacity="0.75" style="mix-blend-mode:difference" filter="url(#f0)"/>
            </mask>
            <g id="card" data-name="Card" transform="matrix(1 0 0 1 0 0)" mask="url(#m1)">
            """))
    }

    /// A lone add mask that is inverted, translucent or feathered is painted in the <mask>, never a hard clip.
    @Test(arguments: [LayerMask(path: MatteRenderListTests.square(10, 90), inverted: true),
                      LayerMask(path: MatteRenderListTests.square(10, 90), opacity: 0.5),
                      LayerMask(path: MatteRenderListTests.square(10, 90), feather: 3)])
    func softLeadingAddMaskIsPaintedNotClipped(_ mask: LayerMask) throws {
        var scene = try Self.scene()
        scene.layers[0].masks = [mask]
        let svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(!svg.contains("<clipPath") && svg.contains("mask=\"url(#m"))
        #expect(svg.contains("fill-rule=\"evenodd\"") == mask.inverted)
        #expect(svg.contains("fill-opacity=\"0.5\"") == (mask.opacity == 0.5))
        #expect(svg.contains("<feGaussianBlur stdDeviation=\"1\"/>") == (mask.feather == 3))
    }

    /// A feathered mask that paints outside its path (inverted, or intersect) blurs over the whole region, not the path's box.
    @Test func featheredOutsideMaskKeepsFullFilterRegion() throws {
        var scene = try Self.scene()
        for mode in [MaskMode.add, .intersect] {
            scene.layers[0].masks = [LayerMask(path: MatteRenderListTests.square(10, 90), mode: mode, feather: 6,
                                               inverted: mode == .add)]
            let svg = try SVGExporter.export(scene: scene, frame: 0)
            #expect(svg.contains("<filter id=\"f0\" filterUnits=\"userSpaceOnUse\"\(Self.region)>"))
            #expect(!svg.contains("x=\"4\" y=\"4\" width=\"92\" height=\"92\""))
        }
    }

    @Test func refusals() throws {
        var scene = try Self.scene()
        scene.layers[0].masks[1].feather = .infinity
        #expect(throws: SVGExportError.nonFiniteValue) { try SVGExporter.export(scene: scene, frame: 0) }
        scene = try Self.scene()
        scene.layers[2].matte = TrackMatte(sourceLayerID: "card")
        #expect(throws: SVGExportError.unsupported("nested matte")) { try SVGExporter.export(scene: scene, frame: 0) }
    }
}
