// PipelineKey.swift: the identity of one compute pipeline in the Metal
// backend's cache: an op family plus a variant string (a blend mode's name, a
// resample filter, an adjustment case; empty for a family with one kernel).
// The key names a Metal kernel function and is the lookup in the binary
// archive, so a variant must be an identifier: `validated` rejects anything
// outside ASCII letters, digits and underscore, and the plain `init` trusts
// its caller (literals in this package). Pure Swift, no Metal import, so it
// builds, tests and mutates on Linux.

/// The identity of one compute pipeline in the Metal backend's cache: the op
/// family and the variant of its kernel. Two keys are equal when both match,
/// so one variant per op family maps to one cached pipeline.
public struct PipelineKey: Hashable, Codable, Sendable {
    /// The op family the pipeline implements.
    public let op: RenderOp

    /// Which kernel of the family: a blend mode's name, a resample filter, an
    /// adjustment case. Empty for a family with one kernel.
    public let variant: String

    /// A key for a literal `op` and `variant`, unchecked: use it for the
    /// variants this package spells out. Use `validated(op:variant:)` for a
    /// variant that comes from outside, since this init never throws.
    public init(op: RenderOp, variant: String = "") {
        self.op = op
        self.variant = variant
    }

    /// The Metal kernel function the key maps to: the op's raw value, then
    /// `_` and the variant when there is one (`composite`,
    /// `composite_multiply`). The cache looks the pipeline up by this name.
    public var functionName: String {
        variant.isEmpty ? op.rawValue : op.rawValue + "_" + variant
    }

    /// A key whose `variant` is checked to be an identifier. Throws
    /// `RenderError.raster("pipeline variant '<v>' must be [A-Za-z0-9_]")`
    /// when any character is outside ASCII letters, digits and underscore,
    /// since the variant becomes part of a function name and of the binary
    /// archive's lookup. An empty variant is valid.
    public static func validated(op: RenderOp, variant: String) throws -> PipelineKey {
        guard variant.unicodeScalars.allSatisfy(isIdentifierScalar) else {
            throw RenderError.raster("pipeline variant '\(variant)' must be [A-Za-z0-9_]")
        }
        return PipelineKey(op: op, variant: variant)
    }

    /// True for `A`-`Z`, `a`-`z`, `0`-`9` and `_`, by code point, so the
    /// check is the same on every platform and locale.
    private static func isIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F: true
        default: false
        }
    }
}
