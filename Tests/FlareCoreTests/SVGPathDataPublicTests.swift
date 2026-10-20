// SVGPathDataPublicTests.swift: SVGExporter.pathData is public API. This file
// imports FlareCore without @testable, so it stops compiling if pathData goes
// back to internal; apps call this one writer instead of keeping a copy.
import FlareCore
import Testing

@Suite struct SVGPathDataPublicTests {
    @Test func pathDataIsCallableWithoutTestable() throws {
        let path = Path(elements: [.move(to: Point(x: 0, y: 0)), .line(to: Point(x: 10, y: 0.5)), .close])
        #expect(try SVGExporter.pathData(path) == "M0 0 L10 0.5 Z")
        let bad = Path(elements: [.move(to: Point(x: .nan, y: 0))])
        #expect(throws: SVGExportError.nonFiniteValue) { try SVGExporter.pathData(bad) }
    }
}
