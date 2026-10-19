// PathBoolean.swift: union, subtract, intersect and exclude of two filled
// paths.
//
// Invariants:
// - the result's filled area is the set operation on the inputs' filled areas
//   under `rule`
// - more than `maxBooleanVertices` flattened vertices throws
//   GeometryError.tooComplex(count) instead of running unbounded
// - output contours are closed, outer counter-clockwise, holes clockwise
//
// ponytail: stub until PG-10; it throws GeometryError.notBuilt with its name.

extension Path {
    /// Most flattened vertices, both inputs together, `combine` accepts.
    public static let maxBooleanVertices = 200_000

    /// `a op b` as one path, each input filled under `rule` and flattened to
    /// `tolerance`.
    ///
    /// Throws `GeometryError.tooComplex` past `maxBooleanVertices` and
    /// `GeometryError.invalidTolerance` for a bad tolerance.
    public static func combine(_ op: BooleanOp, _ a: Path, _ b: Path, rule: FillRule,
                               tolerance: Double) throws -> Path {
        throw GeometryError.notBuilt("combine(_:_:_:rule:tolerance:)")
    }
}
