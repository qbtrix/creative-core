// CoreRenderMetal: the Metal RenderBackend (metal-backend packet). The only
// module allowed to import Metal (CLAUDE.md). Every file here is wrapped whole
// in `#if canImport(Metal)`, so Linux builds this module empty and every other
// module stays Linux-safe. This file is the target scaffold (render-backend
// RB-1); metal-backend MB-1 replaces the marker with MetalBackend.
#if canImport(Metal)
import Metal

/// Marks the CoreRenderMetal module on Apple platforms, where Metal exists.
public enum CoreRenderMetalTarget {
    public static let name = "CoreRenderMetal"
}
#endif
