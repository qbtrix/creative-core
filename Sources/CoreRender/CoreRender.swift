// CoreRender.swift: the marker of the CoreRender module, the render backend
// contract and its CPU backend. CoreRender is Linux-safe, Foundation only, and
// depends on CoreRaster and CoreColor. Backends land in later changes.

/// Names the CoreRender module. Nothing else lives in this file yet.
public enum CoreRenderModule {
    /// The module's name, as SwiftPM knows it.
    public static let name = "CoreRender"
}
