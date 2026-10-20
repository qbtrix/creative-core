// RenderListSamplingTests.swift: the render list draws each shape as it is at the frame, the same values the SVG
// export writes. Fixtures/tracks.flare keys the ball's fill, stroke colour, stroke width and path from 0 to 24;
// trim keys are added here. The stage, hit testing and PNG frames all read the render list, so these pin that
// they see the animation and not the shape's static values.
import Testing
@testable import FlareCore

struct RenderListSamplingTests {
    static let frames: [Double] = [0, 6, 12, 18, 24]

    /// The fixture with the ball's stroke trimmed from 0 to 1 of its outline over 0...24.
    static func scene() throws -> Scene {
        var scene = try TrackCommandsTests.fixtureScene()
        scene.layers[0].tracks[Layer.trackKey(trimEndOf: 0)] = [Keyframe(frame: 0, value: 0), Keyframe(frame: 24, value: 1)]
        return scene
    }

    @Test func itemsCarryTheSampledFillStrokeTrimAndPath() throws {
        let scene = try Self.scene()
        let layer = scene.layers[0]
        for frame in Self.frames {
            let item = try #require(scene.renderList(at: frame, symbols: []).items.first { $0.address.layerID == layer.id })
            let want = layer.sampledShape(0, at: frame)
            #expect(item.fill == want.fill, "fill at \(frame)")
            #expect(item.stroke == want.stroke, "stroke at \(frame)")
            #expect(item.outline == want.outline, "outline at \(frame)")
        }
    }

    @Test func midTweenValuesAreTheInterpolatedOnes() throws {
        let scene = try Self.scene()
        let item = try #require(scene.renderList(at: 12, symbols: []).items.first)
        // fill.0 runs red to blue, strokeWidth.0 2 to 8, trimEnd.0 0 to 1, all linear.
        #expect(item.fill != scene.layers[0].shapes[0].fill)
        #expect(item.stroke?.width == 5)
        #expect(item.stroke?.trim?.end == 0.5)
        #expect(item.outline == scene.layers[0].sampledPath(shape: 0, at: 12))
        #expect(item.outline != scene.layers[0].shapes[0].outline)
    }

    @Test func nodesMatchItems() throws {
        let scene = try Self.scene()
        let list = scene.renderList(at: 12, symbols: [])
        guard case .layer(let layer)? = list.nodes.first, case .shape(_, let shape)? = layer.children.first else {
            Issue.record("no ball node"); return
        }
        let item = try #require(list.items.first)
        #expect(shape.fill == item.fill && shape.stroke == item.stroke && shape.outline == item.outline)
    }

    /// Two instances of one symbol at different symbol frames each draw their own frame's path, not one shared one.
    @Test func instancesAtDifferentFramesMorphApart() throws {
        let fixture = try Self.scene()
        let symbol = Symbol(id: "sym", name: "Sym", durationFrames: 25, layers: fixture.layers)
        let host = Layer(id: "h", name: "H", instances: [
            Instance(symbolID: "sym", firstFrame: 0, loop: .singleFrame),
            Instance(symbolID: "sym", firstFrame: 12, loop: .singleFrame),
        ])
        let list = Scene(id: "s", name: "S", layers: [host]).renderList(at: 0, symbols: [symbol])
        let balls = list.items.filter { $0.address.layerID == fixture.layers[0].id }
        #expect(balls.count == 2)
        #expect(balls.first?.outline == fixture.layers[0].sampledShape(0, at: 0).outline)
        #expect(balls.last?.outline == fixture.layers[0].sampledShape(0, at: 12).outline)
        #expect(balls.last?.stroke?.width == 5)
    }

    /// The SVG export's path line at a frame is the render list item's outline and style, drawn once.
    @Test func svgWritesTheItemsValues() throws {
        let scene = try Self.scene()
        for frame in Self.frames {
            let item = try #require(scene.renderList(at: frame, symbols: []).items.first)
            let svg = try SVGExporter.export(scene: scene, frame: frame)
            #expect(svg.contains("d=\"\(try SVGExporter.pathData(item.outline))\""), "path at \(frame)")
            if case .solid(let color)? = item.fill { #expect(svg.contains(try SVGExporter.fill(color)), "fill at \(frame)") }
        }
    }
}
