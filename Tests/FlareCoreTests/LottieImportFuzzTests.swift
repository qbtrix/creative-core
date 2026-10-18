import Foundation
import Testing
@testable import FlareCore

/// The Lottie reader never crashes on damaged input and keeps to its caps (VI-7).
struct LottieImportFuzzTests {
    func kind(_ json: String) -> String? { ImportFixture.kind { _ = try LottieImport.document(from: Data(json.utf8)) } }
    func file(layers n: Int, width: String = "10") -> String {
        let layers = Array(repeating: "{\"ty\":3,\"ip\":0,\"op\":10,\"st\":0,\"ks\":{}}", count: n).joined(separator: ",")
        return "{\"v\":\"5.7.0\",\"fr\":30,\"ip\":0,\"op\":10,\"w\":\(width),\"h\":10,\"layers\":[\(layers)]}"
    }

    @Test(.disabled("waits on VI-7")) func mutationsThrowOrImport() throws {
        let seeds = try ["shapes.json", "animated.json"].map(ImportFixture.data)
        ImportFuzz.run(seeds: seeds, cases: 1_000, seed: 0x5649_5F37) { data in
            let (document, _) = try LottieImport.document(from: data)
            #expect(throws: Never.self) { try FlareFormat.validate(document) }
        }
    }

    @Test(.disabled("waits on VI-7")) func capsOnBytesAndLayers() {
        #expect(kind(file(layers: 0) + String(repeating: " ", count: LottieImport.maxBytes)) == "tooLarge")
        #expect(kind(file(layers: LottieImport.maxLayers)) == nil)
        #expect(kind(file(layers: LottieImport.maxLayers + 1)) == "tooLarge")
        #expect(kind(file(layers: 1, width: "1e400")) != nil)
    }
}
