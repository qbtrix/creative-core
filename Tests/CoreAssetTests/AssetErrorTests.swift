// AssetErrorTests.swift: CoreAsset's test target. Asset model and manifest
// tests land here.
import CoreAsset
import Testing

@Test func assetErrorsCompareByMessage() {
    #expect(AssetError.invalid("a") == AssetError.invalid("a"))
    #expect(AssetError.invalid("a") != AssetError.invalid("b"))
}
