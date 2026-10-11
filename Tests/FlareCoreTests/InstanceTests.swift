// InstanceTests.swift: symbol instances on layers. Old files decode with no
// instances, instances round-trip byte-stable, and validate rejects instances
// of unknown symbols.
import FlareCore
import Foundation
import Testing

@Suite struct InstanceTests {
    static func documentWithInstances() -> Document {
        var doc = SymbolTests.documentWithSymbols()
        doc.scenes[0].layers[0].instances = [
            Instance(symbolID: "fan", transform: Transform(x: 10, y: 20, scaleX: 2, scaleY: 0.5, rotation: 45)),
            Instance(symbolID: "fan", firstFrame: 3, loop: .playOnce),
            Instance(symbolID: "empty", loop: .singleFrame),
        ]
        doc.symbols[0].layers[0].instances = [Instance(symbolID: "empty")]
        return doc
    }

    @Test func oldLayerDecodesWithNoInstances() throws {
        let json = #"""
        {"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,
          "layers":[{"id":"l","name":"L","shapes":[],"tracks":{}}]}]}}
        """#
        let doc = try FlareFormat.decode(Data(json.utf8))
        #expect(doc.scenes[0].layers[0].instances.isEmpty)
    }

    @Test func instancesRoundTripByteStable() throws {
        let original = Self.documentWithInstances()
        let first = try FlareFormat.encode(original)
        let decoded = try FlareFormat.decode(first)
        #expect(decoded == original)
        #expect(try FlareFormat.encode(decoded) == first)
    }

    @Test func loopModesEncodeAsNames() throws {
        let text = String(decoding: try FlareFormat.encode(Self.documentWithInstances()), as: UTF8.self)
        #expect(text.contains(#""loop" : "loop""#))
        #expect(text.contains(#""loop" : "playOnce""#))
        #expect(text.contains(#""loop" : "singleFrame""#))
    }

    @Test func unknownSymbolThrows() throws {
        var doc = Self.documentWithInstances()
        let layerID = try #require(doc.scenes.first?.layers.first?.id)
        doc.scenes[0].layers[0].instances.append(Instance(symbolID: "ghost"))
        #expect(throws: FormatError.invalid("layer \(layerID): instance of unknown symbol ghost")) {
            try FlareFormat.validate(doc)
        }
        #expect(throws: FormatError.self) { try FlareFormat.encode(doc) }
    }

    @Test func unknownSymbolInsideSymbolThrows() {
        var doc = Self.documentWithInstances()
        doc.symbols[0].layers[0].instances = [Instance(symbolID: "ghost")]
        #expect(throws: FormatError.invalid("layer blade: instance of unknown symbol ghost")) {
            try FlareFormat.validate(doc)
        }
    }

    @Test func unknownSymbolInFileThrows() {
        let json = #"""
        {"format":"flare","version":1,"document":{"symbols":[],"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,
          "layers":[{"id":"l","name":"L","shapes":[],"tracks":{},
            "instances":[{"symbolID":"nope","transform":{"x":0,"y":0,"scaleX":1,"scaleY":1,"rotation":0},
                          "firstFrame":0,"loop":"loop"}]}]}]}}
        """#
        #expect(throws: FormatError.invalid("layer l: instance of unknown symbol nope")) {
            try FlareFormat.decode(Data(json.utf8))
        }
    }

    @Test func negativeFirstFrameThrows() {
        var doc = Self.documentWithInstances()
        doc.scenes[0].layers[0].instances[0].firstFrame = -1
        #expect(throws: FormatError.self) { try FlareFormat.validate(doc) }
    }

    @Test func unknownLoopModeIsMalformed() {
        let json = #"""
        {"format":"flare","version":1,"document":{"symbols":[{"id":"a","name":"A","durationFrames":1,"layers":[]}],
          "scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,
          "layers":[{"id":"l","name":"L","shapes":[],"tracks":{},
            "instances":[{"symbolID":"a","transform":{"x":0,"y":0,"scaleX":1,"scaleY":1,"rotation":0},
                          "firstFrame":0,"loop":"bounce"}]}]}]}}
        """#
        #expect(throws: FormatError.self) { try FlareFormat.decode(Data(json.utf8)) }
    }
}
