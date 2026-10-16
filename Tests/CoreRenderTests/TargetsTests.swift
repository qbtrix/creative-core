// Proves the CoreRender target exists and imports on every platform (RB-1).
import CoreRender
import Testing

@Test func coreRenderImports() {
    #expect(CoreRenderTarget.name == "CoreRender")
}
