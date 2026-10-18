// LayerNodeEqualityTests.swift: LayerNode's hand-written `==`, which walks the
// tree with an explicit stack so a maxDepth-deep compare cannot overflow a
// secondary thread's stack, keeps the synthesized semantics.
import Testing
@testable import CoreRaster

struct LayerNodeEqualityTests {
    func group(_ name: String, _ children: [LayerNode]) -> LayerNode { .group(LayerGroup(name: name, children: children)) }

    @Test func comparesFieldsChildrenAndDepth() throws {
        let leaf = LayerNode.pixels(PixelLayer(name: "a", pixels: try ORAFixtures.pixels(2)))
        #expect(group("g", [leaf]) == group("g", [leaf]))
        #expect(group("g", [leaf]) != group("h", [leaf]))
        #expect(group("g", [leaf]) != group("g", [leaf, leaf]))
        #expect(group("g", [leaf]) != group("g", [group("g", [])]))
        #expect(leaf != group("g", []))
        var deep = leaf, other = LayerNode.pixels(PixelLayer(name: "b", pixels: try ORAFixtures.pixels(2)))
        var same = leaf
        for i in 0..<OpenRaster.maxDepth { deep = group("\(i)", [deep]); same = group("\(i)", [same]); other = group("\(i)", [other]) }
        #expect(deep == same)
        #expect(deep != other)
    }
}
