// Proves CoreRenderMetal imports on every platform: on Apple platforms it holds
// the Metal code, and on Linux it compiles to an empty module (RB-1).
import CoreRenderMetal
import Testing

@Test func coreRenderMetalImports() {
    #if canImport(Metal)
    #expect(CoreRenderMetalTarget.name == "CoreRenderMetal")
    #else
    #expect(Bool(true), "Linux builds CoreRenderMetal empty")
    #endif
}
