// SceneRateTests.swift: a scene's frame rate is an exact fraction (29.97 is 30000/1001), so frame times at the NTSC
// rates don't drift. Whole-rate files read and write exactly as before; a fractional rate writes `frameRate` beside
// the nominal `fps`, and Lottie's `fr` carries the decimal both ways.
import Foundation
import Testing
@testable import FlareCore

struct SceneRateTests {
    static let ntsc = SceneRate(numerator: 30000, denominator: 1001)
    static let film = SceneRate(numerator: 24000, denominator: 1001)

    @Test func ntscIsExact() throws {
        #expect(Self.ntsc.nominal == 30 && !Self.ntsc.isWhole)
        #expect(Self.film.nominal == 24)
        #expect(Self.ntsc.seconds(ofFrame: 300) == 300.0 * 1001 / 30000)
        #expect(try Timeline.time(ofFrame: 300, rate: Self.ntsc) == 10.01)
        #expect(try Timeline.frame(atTime: 10.01, rate: Self.ntsc) == 300)
        #expect(SceneRate(numerator: 60, denominator: 2) == SceneRate(whole: 30), "reduced")
    }

    @Test func wholeRateFilesAreUnchanged() throws {
        let scene = Scene(id: "s", name: "S", fps: 25)
        #expect(scene.rate == SceneRate(whole: 25) && scene.fps == 25)
        let data = try FlareFormat.encode(Document(scenes: [scene]))
        #expect(!String(decoding: data, as: UTF8.self).contains("frameRate"))
        #expect(try FlareFormat.decode(data).scenes.first == scene)
    }

    @Test func fractionalRateRoundTripsInTheFile() throws {
        var scene = Scene(id: "s", name: "S")
        scene.rate = Self.ntsc
        let data = try FlareFormat.encode(Document(scenes: [scene]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"fps\" : 30") && text.contains("\"den\" : 1001") && text.contains("\"num\" : 30000"))
        let back = try #require(try FlareFormat.decode(data).scenes.first)
        #expect(back.rate == Self.ntsc && back == scene)
    }

    @Test func aBadRateIsRefused() throws {
        for (num, den) in [(0, 1), (30, 0), (-24, 1), (24, -1), (1001, 1), (Int.max, 1), (1, Int.max), (Int.min, -1)] {
            var scene = Scene(id: "s", name: "S")
            scene.rate = SceneRate(numerator: num, denominator: den)
            #expect(throws: FormatError.self) { try FlareFormat.encode(Document(scenes: [scene])) }
        }
    }

    /// Any pair of Ints decodes without trapping, and the file is refused unless the rate is valid; any Double
    /// reads as a rate without trapping.
    @Test func fuzzedRatesNeverTrap() throws {
        var rng = SplitMix64(seed: 0x5CE7E)
        let edges = [0, 1, -1, 1001, 30000, Int.max, Int.min, Int(Int32.max)]
        for _ in 0..<500 {
            let num = Bool.random(using: &rng) ? edges.randomElement(using: &rng) ?? 0 : Int.random(in: -1_000_000...2_000_000, using: &rng)
            let den = Bool.random(using: &rng) ? edges.randomElement(using: &rng) ?? 0 : Int.random(in: -10...2_000_000, using: &rng)
            let rate = SceneRate(numerator: num, denominator: den)
            _ = (rate.nominal, rate.isValid, rate.description)
            var scene = Scene(id: "s", name: "S")
            scene.rate = rate
            let text = String(decoding: try JSONEncoder().encode(Document(scenes: [scene])), as: UTF8.self)
            let envelope = Data("{\"format\":\"flare\",\"version\":1,\"document\":\(text)}".utf8)
            if let back = try? FlareFormat.decode(envelope) { #expect(back.scenes.first?.rate.isValid == true) }
            for d in [Double.nan, .infinity, -.infinity, 1e300, -5, Double(num) / 1000] { _ = SceneRate(decimal: d).nominal }
        }
    }

    @Test func setSceneTimingTakesARateAndUndoes() throws {
        var engine = CommandEngine(document: Document(scenes: [Scene(id: "s", name: "S", fps: 24)]))
        try engine.perform(SetSceneTiming(sceneID: "s", fps: 30, durationFrames: 300, rate: Self.ntsc))
        #expect(engine.document.scenes.first?.rate == Self.ntsc && engine.document.scenes.first?.fps == 30)
        try engine.undo()
        #expect(engine.document.scenes.first?.rate == SceneRate(whole: 24))
        try engine.redo()
        // A duration change that passes the nominal fps keeps the exact rate.
        try engine.perform(SetSceneTiming(sceneID: "s", fps: 30, durationFrames: 600))
        #expect(engine.document.scenes.first?.rate == Self.ntsc && engine.document.scenes.first?.durationFrames == 600)
        try engine.perform(SetSceneTiming(sceneID: "s", fps: 25, durationFrames: 10))
        #expect(engine.document.scenes.first?.rate == SceneRate(whole: 25))
        #expect(throws: (any Error).self) {
            try engine.perform(SetSceneTiming(sceneID: "s", fps: 25, durationFrames: 10, rate: SceneRate(numerator: 1, denominator: 0)))
        }
    }

    @Test func pngFramesAreTimedByTheExactRate() throws {
        var scene = Scene(id: "s", name: "S", durationFrames: 400)
        scene.rate = Self.ntsc
        let plan = try PNGExportPlan.plan(scene: scene, frames: 300...300, scale: 1)
        #expect(plan.first?.time == 10.01)
    }

    @Test func lottieWritesAndReadsTheDecimal() throws {
        var scene = Scene(id: "s", name: "S", durationFrames: 30)
        for rate in [Self.ntsc, Self.film, SceneRate(numerator: 60000, denominator: 1001), SceneRate(whole: 24)] {
            scene.rate = rate
            let data = try LottieExporter.export(scene: scene)
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(abs((json["fr"] as? Double ?? 0) - rate.value) < 1e-12, "\(rate)")
            let back = try #require(try LottieImport.document(from: data).0.scenes.first)
            #expect(back.rate == rate, "\(rate)")
        }
        // A file that writes 29.97 rounded still reads as the exact NTSC rate.
        let rounded = Data("{\"fr\":29.97,\"ip\":0,\"op\":10,\"w\":100,\"h\":100,\"layers\":[]}".utf8)
        #expect(try LottieImport.document(from: rounded).0.scenes.first?.rate == Self.ntsc)
    }
}
