import Foundation
import Testing
@testable import FlareCore

/// The import contract (VI-1): the values, the error and the two stubs.
struct ImportShapeTests {
    @Test func svgStubThrowsNotBuilt() {
        let data = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        #expect(throws: ImportError.unsupported("not built")) {
            _ = try SVGImport.scene(from: data, name: "Scene 1")
        }
    }

    @Test func lottieStubThrowsNotBuilt() {
        let data = Data("{\"v\":\"5.7.0\",\"layers\":[]}".utf8)
        #expect(throws: ImportError.unsupported("not built")) {
            _ = try LottieImport.document(from: data)
        }
    }

    @Test func caps() {
        #expect(SVGImport.maxBytes == 32 * 1024 * 1024)
        #expect(SVGImport.maxElements == 200_000)
        #expect(SVGImport.maxDepth == 256)
        #expect(LottieImport.maxBytes == 64 * 1024 * 1024)
        #expect(LottieImport.maxLayers == 5_000)
    }

    @Test func errorsAreEquatable() {
        #expect(ImportError.notThisFormat == .notThisFormat)
        #expect(ImportError.damaged("at 4") == .damaged("at 4"))
        #expect(ImportError.damaged("at 4") != .damaged("at 5"))
        #expect(ImportError.tooLarge("bytes") != .unsupported("bytes"))
        #expect(ImportError.unsupported("not built") != .notThisFormat)
    }

    @Test func reportHoldsSkippedKinds() {
        #expect(ImportReport().skipped.isEmpty)
        let report = ImportReport(skipped: ["filter (3)", "use (1)"])
        #expect(report.skipped == ["filter (3)", "use (1)"])
        #expect(report != ImportReport())
        #expect(Set([report, report]).count == 1)
    }
}
