// ParentTests.swift: a layer may follow another layer of its list (`Layer.parentID`): its matrix is the parent's
// world matrix times its own, so moving or turning the parent carries it. Opacity and visibility are not inherited,
// and a hidden parent still moves its children. Files refuse a missing parent or a cycle, and the command keeps
// undo exact. Lottie's parent is in LottieAnchorParentTests.
import Foundation
import Testing
@testable import FlareCore

struct ParentTests {
    static let unit = Path(polyline: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)], closed: true)

    /// An arm at (100, 100) turning 0 to 90 degrees over 24 frames, and a hand 50 to its right, parented to it.
    static func rig(armVisible: Bool = true) -> Scene {
        var arm = Layer(id: "arm", name: "Arm", shapes: [Shape(points: [], path: unit)])
        arm.tracks = ["x": [Keyframe(frame: 0, value: 100)], "y": [Keyframe(frame: 0, value: 100)],
                      "rotation": [Keyframe(frame: 0, value: 0), Keyframe(frame: 24, value: 90)],
                      "opacity": [Keyframe(frame: 0, value: 0.5)]]
        arm.isVisible = armVisible
        var hand = Layer(id: "hand", name: "Hand", shapes: [Shape(points: [], path: unit)])
        hand.tracks = ["x": [Keyframe(frame: 0, value: 50)]]
        hand.parentID = "arm"
        return Scene(id: "s", name: "S", layers: [arm, hand])
    }

    static func hand(_ scene: Scene, at frame: Double) throws -> RenderItem {
        try #require(scene.renderList(at: frame, symbols: []).items.first { $0.address.layerID == "hand" })
    }

    /// A random parent, none, or a missing one, for UndoPropertyTests.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            let ids = (e.document.layers(of: owner) ?? []).map(\.id) + ["ghost"]
            let parent = Bool.random(using: &rng) ? nil : ids.randomElement(using: &rng)
            try e.perform(SetLayerParent(owner: owner, layerID: layer, parentID: parent))
        },
    ]

    @Test func aChildFollowsItsParent() throws {
        let scene = Self.rig()
        let start = try Self.hand(scene, at: 0).matrix.apply(Point(x: 0, y: 0))
        #expect(start == Point(x: 150, y: 100))
        let turned = try Self.hand(scene, at: 24).matrix.apply(Point(x: 0, y: 0))
        #expect(abs(turned.x - 100) < 1e-9 && abs(turned.y - 150) < 1e-9, "a quarter turn clockwise about the arm")
        #expect(try Self.hand(scene, at: 0).opacity == 1, "opacity isn't inherited")
    }

    /// A chain composes outermost first: a shoulder turned a quarter carries an arm 100 to its right, which
    /// carries a hand 50 further, so the hand ends 150 below the shoulder.
    @Test func aChainComposesFromTheTop() throws {
        var scene = Self.rig()
        var shoulder = Layer(id: "shoulder", name: "Shoulder")
        shoulder.tracks = ["rotation": [Keyframe(frame: 0, value: 90)]]
        scene.layers.insert(shoulder, at: 0)
        scene.layers[1].tracks = ["x": [Keyframe(frame: 0, value: 100)]]
        scene.layers[1].parentID = "shoulder"
        let hand = try Self.hand(scene, at: 0).matrix.apply(Point(x: 0, y: 0))
        #expect(abs(hand.x) < 1e-9 && abs(hand.y - 150) < 1e-9, "\(hand)")
    }

    @Test func aHiddenParentStillMovesItsChild() throws {
        let scene = Self.rig(armVisible: false)
        let list = scene.renderList(at: 24, symbols: [])
        #expect(!list.items.contains { $0.address.layerID == "arm" })
        let turned = try Self.hand(scene, at: 24).matrix.apply(Point(x: 0, y: 0))
        #expect(abs(turned.x - 100) < 1e-9 && abs(turned.y - 150) < 1e-9)
    }

    @Test func svgWritesTheParentedMatrix() throws {
        let scene = Self.rig()
        let svg = try SVGExporter.export(scene: scene, frame: 24)
        let world = try Self.hand(scene, at: 24).matrix
        #expect(svg.contains(try SVGExporter.matrix(world)))
    }

    @Test func filesRefuseAMissingParentOrACycle() throws {
        var missing = Self.rig()
        missing.layers[1].parentID = "ghost"
        #expect(throws: FormatError.self) { try FlareFormat.encode(Document(scenes: [missing])) }
        var loop = Self.rig()
        loop.layers[0].parentID = "hand"
        #expect(throws: FormatError.self) { try FlareFormat.encode(Document(scenes: [loop])) }
        var own = Self.rig()
        own.layers[1].parentID = "hand"
        #expect(throws: FormatError.self) { try FlareFormat.encode(Document(scenes: [own])) }
    }

    @Test func theParentRoundTripsAndOldLayersHaveNone() throws {
        let data = try FlareFormat.encode(Document(scenes: [Self.rig()]))
        #expect(try FlareFormat.decode(data).scenes.first?.layers.last?.parentID == "arm")
        let plain = try FlareFormat.encode(Document(scenes: [Scene(id: "s", name: "S", layers: [Layer(id: "l", name: "L")])]))
        #expect(!String(decoding: plain, as: UTF8.self).contains("parent"))
    }

    @Test func setLayerParentRefusesACycleAndUndoes() throws {
        var scene = Self.rig()
        scene.layers[1].parentID = nil
        var engine = CommandEngine(document: Document(scenes: [scene]))
        let owner = LayerOwner.scene("s")
        try engine.perform(SetLayerParent(owner: owner, layerID: "hand", parentID: "arm"))
        #expect(engine.document.scenes.first?.layers.last?.parentID == "arm")
        // The command names the cycle itself, before the format check would.
        #expect(throws: CommandError.invalidDocument("hand already follows arm, so arm can't follow it.")) {
            try engine.perform(SetLayerParent(owner: owner, layerID: "arm", parentID: "hand"))
        }
        #expect(throws: CommandError.self) { try engine.perform(SetLayerParent(owner: owner, layerID: "arm", parentID: "ghost")) }
        try engine.undo()
        #expect(engine.document.scenes.first?.layers.last?.parentID == nil)
        // Removing a parent while a child follows it is refused, as removing a matte source is.
        try engine.redo()
        #expect(throws: (any Error).self) { try engine.perform(RemoveLayer(owner: owner, layerID: "arm")) }
    }
}
