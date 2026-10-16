// TargetsTests.swift: CoreRender's target check. Importing the module and
// reading its marker proves the target builds and links.
import CoreRender
import Testing

@Test func coreRenderModuleIsNamed() {
    #expect(CoreRenderModule.name == "CoreRender")
}
