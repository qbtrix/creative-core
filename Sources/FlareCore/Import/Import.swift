// Import.swift: the contract of the vector importers, the inverse of export.
//
// `SVGImport` reads one SVG document into one `Scene` (its `viewBox`, else
// `width`/`height`, else 1000 x 1000, gives the scene size); `LottieImport`
// reads one Lottie JSON document into a `Document`. Both follow the public
// specs only (W3C SVG 1.1 and SVG 2, the published Lottie format). Each reader
// checks the byte size first and counts elements or layers and depth as it
// goes, throwing `ImportError.tooLarge` past the caps below. What a reader
// does not turn into the model it lists in the `ImportReport` instead of
// dropping it in silence. Until the readers are built, both entry points
// throw `ImportError.unsupported("not built")`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// What an import skipped: one entry per kind with its count, such as
/// "filter (3)" or "use (1)".
public struct ImportReport: Sendable, Hashable {
    public var skipped: [String]

    public init(skipped: [String] = []) {
        self.skipped = skipped
    }
}

/// The error every importer throws.
public enum ImportError: Error, Equatable, Sendable {
    /// The bytes are not this importer's format at all.
    case notThisFormat
    /// The bytes are the format but broken; the string says where and how.
    case damaged(String)
    /// The input passes a size, count or depth cap; the string names it.
    case tooLarge(String)
    /// The input uses something this importer cannot read; the string says what.
    case unsupported(String)
}

/// Reads an SVG document into one scene.
public enum SVGImport {
    /// The largest SVG accepted, in bytes.
    public static let maxBytes = 32 << 20
    /// The most elements read from one document.
    public static let maxElements = 200_000
    /// The deepest element nesting read.
    public static let maxDepth = 256

    /// One scene named `name` from the SVG in `data`, with what was skipped.
    public static func scene(from data: Data, name: String) throws -> (Scene, ImportReport) {
        throw ImportError.unsupported("not built")
    }
}

/// Reads a Lottie JSON document into a document.
public enum LottieImport {
    /// The largest Lottie file accepted, in bytes.
    public static let maxBytes = 64 << 20
    /// The most layers read from one file.
    public static let maxLayers = 5_000

    /// The document in the Lottie JSON `data`, with what was skipped.
    public static func document(from data: Data) throws -> (Document, ImportReport) {
        throw ImportError.unsupported("not built")
    }
}
