// SceneCanvasTests.swift: Scene width, height and background. Old v1 files
// without the fields get the defaults, a round trip stays byte-stable, and a
// non-positive or non-finite size is rejected.
import FlareCore
import Foundation
import Testing

@Suite struct SceneCanvasTests {
    @Test func v1FileWithoutCanvasFieldsGetsDefaults() throws {
        let json = #"""
        {"format":"flare","version":1,
         "document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,"layers":[]}]}}
        """#
        let scene = try #require(try FlareFormat.decode(Data(json.utf8)).scenes.first)
        #expect(scene.width == 550)
        #expect(scene.height == 400)
        #expect(scene.background == Color.white)
    }

    @Test func canvasFieldsDecodeAndRoundTripByteStable() throws {
        let json = #"""
        {"format":"flare","version":1,
         "document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,"layers":[],
           "width":1920,"height":1080,"background":{"r":0.5,"g":0.25,"b":0,"a":1}}]}}
        """#
        let doc = try FlareFormat.decode(Data(json.utf8))
        let scene = try #require(doc.scenes.first)
        #expect(scene.width == 1920)
        #expect(scene.height == 1080)
        #expect(scene.background == Color(r: 0.5, g: 0.25, b: 0))
        let first = try FlareFormat.encode(doc)
        #expect(try FlareFormat.decode(first) == doc)
        #expect(try FlareFormat.encode(FlareFormat.decode(first)) == first)
    }

    @Test func zeroWidthThrowsInvalid() {
        let json = #"""
        {"format":"flare","version":1,
         "document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,"layers":[],"width":0}]}}
        """#
        #expect {
            try FlareFormat.decode(Data(json.utf8))
        } throws: { error in
            guard case FormatError.invalid = error else { return false }
            return true
        }
    }

    @Test(arguments: [0, -1, Double.nan, Double.infinity, -Double.infinity])
    func badSizeIsRejectedByValidate(_ bad: Double) {
        for useWidth in [true, false] {
            var scene = Scene(id: "s", name: "S")
            if useWidth { scene.width = bad } else { scene.height = bad }
            #expect(throws: FormatError.self) { try FlareFormat.validate(Document(scenes: [scene])) }
        }
    }
}
