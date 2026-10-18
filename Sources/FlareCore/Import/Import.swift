// Import.swift: the contract of the vector importers, the inverse of export.
//
// `SVGImport` reads one SVG document into one `Scene` (its `viewBox`, else
// `width`/`height`, else 1000 x 1000, gives the scene size); `LottieImport`
// reads one Lottie JSON document into a `Document`. Both follow the public
// specs only (W3C SVG 1.1 and SVG 2, the published Lottie format). Each reader
// checks the byte size first and counts elements or layers and depth as it
// goes, throwing `ImportError.tooLarge` past the caps below. What a reader
// does not turn into the model it lists in the `ImportReport` instead of
// dropping it in silence. Until the SVG reader is built, it throws
// `ImportError.unsupported("not built")`; Lottie is in LottieImport.swift.
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
    /// The largest SVG accepted: `data.count`, in bytes (32 MiB). Checked
    /// first, before any byte is read: exactly `maxBytes` bytes are read, and
    /// `maxBytes + 1` throws `ImportError.tooLarge` at once.
    public static let maxBytes = 32 << 20
    /// The most elements in one document: every start tag counts (a
    /// self-closing tag is one, and skipped kinds such as `filter` count too;
    /// end tags, text and comments do not). The 200,000th element is read;
    /// the 200,001st throws `ImportError.tooLarge`.
    public static let maxElements = 200_000
    /// The deepest element nesting: the root `<svg>` is depth 1 and each open
    /// child adds one. An element at depth 256 is read; one at depth 257
    /// throws `ImportError.tooLarge`. It also bounds a gradient `href` or
    /// `clip-path` reference chain: past 256 links the reference is dropped
    /// and counted in the report as a cycle, never thrown.
    public static let maxDepth = 256

    /// One scene named `name` from the SVG in `data`, with what was skipped.
    public static func scene(from data: Data, name: String) throws -> (Scene, ImportReport) {
        throw ImportError.unsupported("not built")
    }
}

/// Reads a Lottie JSON document into a document.
public enum LottieImport {
    /// The largest Lottie file accepted: `data.count`, in bytes (64 MiB).
    /// Checked first, before the JSON is decoded: exactly `maxBytes` bytes are
    /// read, and `maxBytes + 1` throws `ImportError.tooLarge` at once.
    public static let maxBytes = 64 << 20
    /// The most layers in one file: every entry of the top-level `layers`
    /// array counts, skipped kinds (precomps, images, text) included. The
    /// 5,000th layer is read; the 5,001st throws `ImportError.tooLarge`.
    public static let maxLayers = 5_000
    /// The deepest `gr` nesting read: 256 groups read, the 257th throws `tooLarge`.
    public static let maxDepth = 256

    /// The document in the Lottie JSON `data`, with what was skipped.
    public static func document(from data: Data) throws -> (Document, ImportReport) {
        try read(data)
    }
}
