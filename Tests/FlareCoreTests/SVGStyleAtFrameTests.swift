// SVGStyleAtFrameTests.swift: SVG writes Fixtures/tracks.flare's sampled fill, stroke, width and path at the
// exported frame (AP-8); with nothing keyed, frame 0 is the static export.
import Testing
@testable import FlareCore

struct SVGStyleAtFrameTests {
    /// The fixture shape's `<path .../>` line at `frame`.
    static func pathLine(at frame: Double) throws -> String {
        try pathLine(in: SVGExporter.export(scene: TrackCommandsTests.fixtureScene(), frame: frame))
    }

    static func pathLine(in svg: String) throws -> String {
        try #require(svg.split(separator: "\n").first { $0.hasPrefix("<path ") }.map(String.init))
    }

    @Test func usesSampledColour() throws {
        let line = try Self.pathLine(at: 24)
        #expect(line.contains("fill=\"#0000ff\"") && line.contains("stroke=\"#ffffff\""))
    }

    @Test func usesSampledWidth() throws { #expect(try Self.pathLine(at: 12).contains("stroke-width=\"5\"")) }

    @Test func usesSampledPath() throws {
        let mid = try #require(try TrackCommandsTests.fixtureScene().layers.first?.sampledPath(shape: 0, at: 12))
        #expect(try SVGExporter.pathData(mid).hasPrefix("M7.5 7.5 L20 0"))
        #expect(try Self.pathLine(at: 12).contains("d=\"\(try SVGExporter.pathData(mid))\""))
    }

    @Test func frameZeroStaticWhenUnkeyed() throws {
        var scene = try TrackCommandsTests.fixtureScene()
        let keyed = try SVGExporter.export(scene: scene, frame: 0)
        (scene.layers[0].colorTracks, scene.layers[0].shapeTracks) = ([:], [])
        scene.layers[0].tracks["strokeWidth.0"] = nil
        // Every frame-0 key equals the static value, so the keyed and unkeyed exports match.
        #expect(keyed == (try SVGExporter.export(scene: scene, frame: 0)))
    }

    @Test func symbolLayersSampleAtTheSymbolFrame() throws {
        let fixture = try TrackCommandsTests.fixtureScene()
        let symbol = Symbol(id: "sym", name: "Sym", durationFrames: 24, layers: fixture.layers)
        let host = Layer(id: "h", name: "H", instances: [Instance(symbolID: "sym", firstFrame: 12, loop: .singleFrame)])
        let scene = Scene(id: "s", name: "S", layers: [host])
        // Host frame 0 shows symbol frame 12: the fixture's frame-12 fill, stroke, width and path.
        let line = try Self.pathLine(in: SVGExporter.export(scene: scene, frame: 0, symbols: [symbol]))
        let (twelve, zero) = (try Self.pathLine(at: 12), try Self.pathLine(at: 0))
        #expect(line == twelve && line != zero)
    }

    @Test func tracksOnlyRestyleThePaintTheShapeHas() throws {
        var scene = try TrackCommandsTests.fixtureScene()
        let stops = [GradientStop(offset: 0, color: .black), GradientStop(offset: 1, color: .white)]
        scene.layers[0].shapes[0].fill = .linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 40, y: 0))
        scene.layers[0].tracks["strokeWidth.0"] = [Keyframe(frame: 0, value: -3)]
        let gradient = try Self.pathLine(in: SVGExporter.export(scene: scene, frame: 24))
        #expect(gradient.contains("fill=\"url(#g0)\"") && gradient.contains("stroke-width=\"0\""))
        scene.layers[0].shapes[0].stroke = nil
        #expect(!(try Self.pathLine(in: SVGExporter.export(scene: scene, frame: 24))).contains("stroke"))
    }
}
