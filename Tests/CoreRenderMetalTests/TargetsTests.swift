// Proves CoreRenderMetal imports on every platform: on Apple platforms it holds
// the Metal backend, and on Linux it compiles to an empty module (RB-1, MB-1).
import CoreRenderMetal
import Testing

@Test func coreRenderMetalImports() {
    #if canImport(Metal)
    let device = MetalBackend.defaultDevice
    #expect(device == nil || device?.name.isEmpty == false, "a runner without a GPU has no default device")
    #else
    #expect(Bool(true), "Linux builds CoreRenderMetal empty")
    #endif
}
