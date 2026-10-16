import Foundation
import Testing
@testable import FlareCore

/// Gradient stop alpha: `g.k` holds the color stops, then the alpha stops
/// only when some stop is translucent; `g.p` counts the stops once.
struct LottieGradientAlphaTests {
    private let square = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1)]

    private func stops(endAlpha: Double) -> [GradientStop] {
        [GradientStop(offset: 0, color: Color(r: 1, g: 0, b: 0)),
         GradientStop(offset: 1, color: Color(r: 0, g: 0, b: 1, a: endAlpha))]
    }

    /// A one-layer scene with a linear then a radial gradient fill.
    private func exported(_ stops: [GradientStop]) throws -> String {
        let scene = Scene(id: "s", name: "S", layers: [Layer(id: "a", name: "A", shapes: [
            Shape(points: square, fill: .linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 4, y: 0))),
            Shape(points: square, fill: .radial(stops: stops, center: Point(x: 2, y: 3), radius: 5)),
        ])])
        return String(decoding: try LottieExporter.export(scene: scene), as: UTF8.self)
    }

    @Test func translucentStopAppendsAlphaStopsToLinearAndRadial() throws {
        let text = try exported(stops(endAlpha: 0.25))
        let linear = #"{"e":{"a":0,"k":[4,0]},"g":{"k":{"a":0,"k":[0,1,0,0,1,0,0,1,0,1,1,0.25]},"p":2},"o":{"a":0,"k":100},"r":1,"s":{"a":0,"k":[0,0]},"t":1,"ty":"gf"}"#
        let radial = #"{"e":{"a":0,"k":[7,3]},"g":{"k":{"a":0,"k":[0,1,0,0,1,0,0,1,0,1,1,0.25]},"p":2},"o":{"a":0,"k":100},"r":1,"s":{"a":0,"k":[2,3]},"t":2,"ty":"gf"}"#
        #expect(text.contains(linear))
        #expect(text.contains(radial))
    }

    /// Captured from `dev` before alpha stops were written.
    @Test func opaqueGradientKeepsTodaysBytes() throws {
        let golden = #"{"assets":[],"ddd":0,"fr":24,"h":400,"ip":0,"layers":[{"ddd":0,"hd":false,"ind":1,"ip":0,"ks":{"a":{"a":0,"k":[0,0]},"o":{"a":0,"k":100},"p":{"a":0,"k":[0,0]},"r":{"a":0,"k":0},"s":{"a":0,"k":[100,100]}},"nm":"A","op":48,"shapes":[{"it":[{"ks":{"a":0,"k":{"c":true,"i":[[0,0],[0,0],[0,0]],"o":[[0,0],[0,0],[0,0]],"v":[[0,0],[1,0],[1,1]]}},"ty":"sh"},{"e":{"a":0,"k":[4,0]},"g":{"k":{"a":0,"k":[0,1,0,0,1,0,0,1]},"p":2},"o":{"a":0,"k":100},"r":1,"s":{"a":0,"k":[0,0]},"t":1,"ty":"gf"},{"a":{"a":0,"k":[0,0]},"o":{"a":0,"k":100},"p":{"a":0,"k":[0,0]},"r":{"a":0,"k":0},"s":{"a":0,"k":[100,100]},"ty":"tr"}],"ty":"gr"},{"it":[{"ks":{"a":0,"k":{"c":true,"i":[[0,0],[0,0],[0,0]],"o":[[0,0],[0,0],[0,0]],"v":[[0,0],[1,0],[1,1]]}},"ty":"sh"},{"e":{"a":0,"k":[7,3]},"g":{"k":{"a":0,"k":[0,1,0,0,1,0,0,1]},"p":2},"o":{"a":0,"k":100},"r":1,"s":{"a":0,"k":[2,3]},"t":2,"ty":"gf"},{"a":{"a":0,"k":[0,0]},"o":{"a":0,"k":100},"p":{"a":0,"k":[0,0]},"r":{"a":0,"k":0},"s":{"a":0,"k":[100,100]},"ty":"tr"}],"ty":"gr"}],"sr":1,"st":0,"ty":4}],"nm":"S","op":48,"v":"5.7.0","w":550}"#
        #expect(try exported(stops(endAlpha: 1)) == golden)
        // An alpha above 1 clamps to opaque and writes no alpha stops either.
        #expect(try exported(stops(endAlpha: 1.5)) == golden)
    }

    @Test func nonFiniteAlphaThrows() {
        #expect(throws: LottieExportError.nonFiniteValue) { try exported(stops(endAlpha: .nan)) }
        #expect(throws: LottieExportError.nonFiniteValue) { try exported(stops(endAlpha: .infinity)) }
    }
}
