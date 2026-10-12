// CatalogErrorTests.swift: CoreCatalog's test target. Schema, migration and
// query tests land here. The SQLite check proves GRDB links the system SQLite
// on every CI platform before any catalog code depends on it.
import CoreCatalog
import GRDB
import Testing

@Test func catalogErrorsCompareByMessage() {
    #expect(CatalogError.invalid("a") == CatalogError.invalid("a"))
    #expect(CatalogError.invalid("a") != CatalogError.invalid("b"))
}

@Test func inMemorySQLiteOpensAndAnswers() throws {
    let db = try DatabaseQueue()
    let one = try db.read { try Int.fetchOne($0, sql: "SELECT 1") }
    #expect(one == 1)
}
