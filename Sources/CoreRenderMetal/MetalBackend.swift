// MetalBackend.swift: the Metal render backend of CoreRender. The whole file is
// compiled only where Metal exists, so on Linux the CoreRenderMetal module is empty.
#if canImport(Metal)
/// Names the CoreRenderMetal module on platforms with Metal.
public enum CoreRenderMetalModule {
    /// The module's name, as SwiftPM knows it.
    public static let name = "CoreRenderMetal"
}
#endif
