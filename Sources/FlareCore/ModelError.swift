// ModelError.swift: the error the model layer throws (Document lookups, fill
// text and stroke validation). The model never names an error of the layers above it; the
// command and format layers each map this to their own error type, in one
// initializer beside that type.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum ModelError: Error, Equatable, Sendable {
    case sceneNotFound(String)
    case symbolNotFound(String)
    case layerNotFound(String)
    /// The layer is locked, so its content cannot be edited.
    case layerLocked(String)
    /// A fill breaks an invariant listed in Fill.swift; the string says which.
    case invalidFill(String)
    /// A text shape breaks an invariant listed beside `TextShape`, or the metrics given to
    /// `TextLayout.lay` / `GlyphRunMetrics.init` do not fit it; the string says which.
    case invalidText(String)
    /// A stroke breaks an invariant listed beside `Stroke`.
    case invalidStroke(String)
}
