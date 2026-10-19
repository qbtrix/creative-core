// SVGMaskExportTests.swift: MM-8 acceptance for SVG layer masks (clipPath, mask,
// blur of feather / 2) and track mattes (mask holding the source), and refusals.
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
            <filter id="f1" filterUnits="userSpaceOnUse" x="18" y="18" width="64" height="64">
            <feGaussianBlur stdDeviation="4"/>
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

    @Test func blurIsHalfFeather() throws {
        var scene = try Self.scene()
        scene.layers[0].masks[1].feather = 3
        let svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(svg.contains("<feGaussianBlur stdDeviation=\"1.5\"/>"))
        #expect(svg.contains("x=\"25.5\" y=\"25.5\" width=\"49\" height=\"49\""))
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

    @Test func refusals() throws {
        var scene = try Self.scene()
        scene.layers[0].masks[1].mode = .difference
        #expect(throws: SVGExportError.unsupported("mask difference")) { try SVGExporter.export(scene: scene, frame: 0) }
        scene = try Self.scene()
        scene.layers[0].masks[1].feather = .infinity
        #expect(throws: SVGExportError.nonFiniteValue) { try SVGExporter.export(scene: scene, frame: 0) }
        scene = try Self.scene()
        scene.layers[2].matte = TrackMatte(sourceLayerID: "card")
        #expect(throws: SVGExportError.unsupported("nested matte")) { try SVGExporter.export(scene: scene, frame: 0) }
    }
}
