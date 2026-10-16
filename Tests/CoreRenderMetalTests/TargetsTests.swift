// TargetsTests.swift: CoreRenderMetal's target check. The module is empty on
// Linux, so the marker is checked only where Metal exists; the import always compiles.
import CoreRenderMetal
import Testing

@Test func coreRenderMetalModuleIsNamed() {
    #if canImport(Metal)
    #expect(CoreRenderMetalModule.name == "CoreRenderMetal")
    #endif
}
