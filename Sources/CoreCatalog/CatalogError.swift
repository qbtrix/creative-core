// CatalogError.swift: the one error type of CoreCatalog, the photo and
// metadata catalog over SQLite. CoreCatalog is Linux-safe and depends only on
// GRDB (the one approved dependency, for this module only). Every throwing API
// in this module throws this; GRDB's errors are mapped to it, never rethrown.
public enum CatalogError: Error, Equatable, Sendable {
    /// A value, rule or query parameter is malformed or out of range.
    case invalid(String)
}
