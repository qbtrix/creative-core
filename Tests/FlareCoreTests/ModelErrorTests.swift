// ModelErrorTests.swift: the model throws ModelError, the command and format
// layers map it to their own errors, and no model file names a type from the
// layers above it.
@testable import FlareCore
import Foundation
import Testing

@Suite struct ModelErrorTests {
    static let s = Fixtures.sceneID

    @Test func lookupsThrowModelError() throws {
        var doc = Fixtures.document()
        #expect(throws: ModelError.sceneNotFound("nope")) { try doc.sceneIndex("nope") }
        #expect(throws: ModelError.sceneNotFound("nope")) { try doc.withLayer(scene: "nope", layer: "ball") { _ in } }
        #expect(throws: ModelError.layerNotFound("ghost")) { try doc.withLayer(scene: Self.s, layer: "ghost") { _ in } }
        doc.scenes[0].layers[1].isLocked = true
        #expect(throws: ModelError.layerLocked("ball")) {
            try doc.withEditableLayer(scene: Self.s, layer: "ball") { $0.name = "X" }
        }
        #expect(doc.scenes[0].layers[1].name == "Ball")
        #expect(try doc.sceneIndex(Self.s) == 0)
    }

    @Test func fillValidateThrowsModelError() {
        let fill = Fill.radial(stops: [], center: Point(x: 0, y: 0), radius: 0)
        #expect(throws: ModelError.invalidFill("radial gradient radius must be finite and > 0")) { try fill.validate() }
    }

    @Test func commandLayerMapsModelErrors() {
        #expect(CommandError(ModelError.sceneNotFound("a")) == .sceneNotFound("a"))
        #expect(CommandError(ModelError.symbolNotFound("s")) == .symbolNotFound("s"))
        #expect(CommandError(ModelError.layerNotFound("b")) == .layerNotFound("b"))
        #expect(CommandError(ModelError.layerLocked("c")) == .layerLocked("c"))
        #expect(CommandError(ModelError.invalidFill("d")) == .invalidDocument("d"))
        var engine = CommandEngine(document: Fixtures.document())
        #expect(throws: CommandError.layerNotFound("ghost")) {
            try engine.perform(RenameLayer(sceneID: Self.s, layerID: "ghost", name: "X"))
        }
    }

    @Test func formatLayerMapsModelErrors() {
        #expect(FormatError(ModelError.invalidFill("d")) == .invalid("d"))
        #expect(FormatError(ModelError.symbolNotFound("s")) == .invalid("symbolNotFound(\"s\")"))
        var doc = Fixtures.document()
        doc.scenes[0].layers[1].shapes[0].fill = .radial(stops: [], center: Point(x: 0, y: 0), radius: -1)
        #expect(throws: FormatError.invalid("radial gradient radius must be finite and > 0")) {
            try FlareFormat.validate(doc)
        }
    }

    /// The model list in docs/engineering.md. A model file that names a
    /// command or format type depends on a layer above it.
    @Test func modelFilesNameNoUpperLayerType() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FlareCore")
        let modelFiles = ["Document", "Fill", "Path", "Geometry", "Symbols", "Instance", "StateMachine",
                          "MachineInputs", "ModelError", "LayerOwner"]
        let forbidden = ["CommandError", "FormatError", "FlareFormat"]
        for name in modelFiles {
            let text = try String(contentsOf: sources.appendingPathComponent("\(name).swift"), encoding: .utf8)
            for word in forbidden {
                #expect(!text.contains(word), "\(name).swift names \(word)")
            }
            let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            #expect(!words.contains("Command"), "\(name).swift names Command")
        }
    }
}
