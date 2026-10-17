// Proves CoreRenderMetal imports on every platform: on Apple platforms it holds
// the Metal backend, and on Linux it compiles to an empty module (RB-1, MB-1).
import CoreRenderMetal
import Testing

@Test func coreRenderMetalImports() {
    #if canImport(Metal)
    let device = MetalBackend.defaultDevice
    print("CoreRenderMetal: default device \(device?.name ?? "none")")
    #expect(device == nil || device?.name.isEmpty == false, "a runner without a GPU has no default device")
    #else
    // On Linux the proof is the build itself: this file imports CoreRenderMetal and compiles
    // against an empty module, so there is nothing to assert at run time.
    #endif
}
