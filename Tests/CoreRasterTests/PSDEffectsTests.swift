// PSDEffectsTests.swift: layer styles in PSD files (layer-style-engine LE-1,
// LE-6). The new model fields' defaults and a round trip that carries none run
// now; reading `lfx2` into `PixelLayer.style` waits on LE-6.
import CoreRaster
import Foundation
import Testing

@Suite struct PSDEffectsTests {
    private func oneLayer() throws -> LayeredImage {
        let layer = PixelLayer(name: "badge", pixels: try StyleFixtures.badge())
        return LayeredImage(width: 48, height: 32, nodes: [.pixels(layer)])
    }

    @Test func aFileWithoutEffectsReadsNoStyleAndNoNotes() throws {
        #expect(try oneLayer().notes.isEmpty)
        let read = try PSD.read(PSD.write(oneLayer()))
        #expect(read.notes.isEmpty)
        guard case let .pixels(layer)? = read.nodes.first else { Issue.record("no layer"); return }
        #expect(layer.style == nil)
    }

    @Test(.disabled("waits on LE-6")) func styleSurvivesAWriteAndRead() throws {
        var image = try oneLayer()
        guard case var .pixels(layer)? = image.nodes.first else { Issue.record("no layer"); return }
        layer.style = StyleFixtures.everyOp()
        image.nodes = [.pixels(layer)]
        let read = try PSD.read(PSD.write(image))
        guard case let .pixels(back)? = read.nodes.first else { Issue.record("no layer"); return }
        #expect(back.style?.entries.count == 7)
    }
}
