// SVGStyleAtFrameTests.swift: SVG writes Fixtures/tracks.flare's sampled fill, stroke, width and path at the
// exported frame (AP-8); with nothing keyed, frame 0 is the static export.
import Testing
@testable import FlareCore

@Suite(.disabled("AP-8 turns this on"))
struct SVGStyleAtFrameTests {
    /// The fixture shape's `<path .../>` line at `frame`.
    static func pathLine(at frame: Double) throws -> String {
        let svg = try SVGExporter.export(scene: TrackCommandsTests.fixtureScene(), frame: frame)
        return try #require(svg.split(separator: "\n").first { $0.hasPrefix("<path ") }.map(String.init))
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
}
