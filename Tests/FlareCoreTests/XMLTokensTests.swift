import Foundation
import Testing
@testable import FlareCore

/// The bounded XML tokenizer (VI-3), checked through a neutral token shape.
struct XMLTokensTests {
    enum Token: Equatable { case start(String, [String: String], selfClosing: Bool), end(String), text(String) }

    func tokens(_ xml: String) throws -> [Token] {
        try XMLTokens.tokens(Data(xml.utf8)).map { token in
            switch token {
            case let .start(name, attributes, selfClosing):
                .start(name, Dictionary(attributes.map { ($0.name, $0.value) }, uniquingKeysWith: { a, _ in a }), selfClosing: selfClosing)
            case let .end(name): .end(name)
            case let .text(text): .text(text)
            }
        }
    }
    func open(_ name: String, _ attributes: [String: String] = [:]) -> Token { .start(name, attributes, selfClosing: false) }
    func empty(_ name: String, _ attributes: [String: String] = [:]) -> Token { .start(name, attributes, selfClosing: true) }

    /// Tags, text and self-closing tags; attributes in both quote styles; CDATA and declarations skipped.
    @Test func tagsAttributesAndDeclarations() throws {
        #expect(try tokens("<a><b>hi</b><c/></a>") == [open("a"), open("b"), .text("hi"), .end("b"), empty("c"), .end("a")])
        #expect(try tokens("<p x=\"1\" y='two words' z = \"a'b\"/>") == [empty("p", ["x": "1", "y": "two words", "z": "a'b"])])
        #expect(try tokens("<?xml version=\"1.0\"?><a><![CDATA[<b/>]]></a>") == [open("a"), .end("a")])
    }

    @Test func skipsComments() throws {
        #expect(try tokens("<a><!-- a -> b --><b/></a>") == [open("a"), empty("b"), .end("a")])
    }

    @Test func decodesEntities() throws {
        #expect(try tokens("<a t=\"&quot;&apos;\">&lt;&gt;&amp;&quot;&apos;&#65;&#x42;</a>") == [open("a", ["t": "\"'"]), .text("<>&\"'AB"), .end("a")])
    }

    @Test func damagedInputThrows() {
        for xml in ["<a", "<a b=\"1></a>", "<a>&bogus;</a>", "<a>&#xZZ;</a>"] { #expect(throws: ImportError.self, "\(xml)") { _ = try tokens(xml) } }
        // Numeric references that would break a scalar conversion or an integer parse.
        for xml in ["<a>&#xD800;</a>", "<a>&#x110000;</a>", "<a>&#0;</a>", "<a>&#99999999999999999999999;</a>", "<a t=\"&#xD800;\"/>"] {
            #expect(throws: ImportError.self, "\(xml)") { _ = try tokens(xml) }
        }
    }

    @Test func depthCapped() throws {
        func nested(_ n: Int) -> String { String(repeating: "<g>", count: n) + String(repeating: "</g>", count: n) }
        #expect(try tokens(nested(SVGImport.maxDepth)).count == 2 * SVGImport.maxDepth)
        #expect(throws: ImportError.self) { _ = try tokens(nested(SVGImport.maxDepth + 1)) }
    }

    @Test func capsAndReferencesThrow() throws {
        for xml in ["<a>&#+65;</a>", "<a></b>", "<a x='1' x='2'/>", "<!-- open"] {
            #expect(throws: ImportError.self, "\(xml)") { _ = try tokens(xml) }
        }
        #expect(throws: ImportError.tooLarge("XML is over 4 bytes")) { _ = try XMLTokens.tokens(Data("<a/>x".utf8), maxBytes: 4) }
        #expect(throws: ImportError.tooLarge("more than 1 elements")) { _ = try XMLTokens.tokens(Data("<a/><b/>".utf8), maxElements: 1) }
        #expect(try tokens("<!DOCTYPE svg [<!ENTITY x \"]>\">]><a>&#x1F600;</a>") == [open("a"), .text("\u{1F600}"), .end("a")])
    }

    /// 1,000 seeded mutations of a small document tokenize or throw an `ImportError`, never crash.
    @Test func fuzzThrowsInsteadOfCrashing() {
        let seed = Data("<?xml version=\"1.0\"?><!-- c --><svg a=\"1\" b='&amp;&#65;'><g><path d=\"M0 0\"/>t&lt;</g><![CDATA[x]]></svg>".utf8)
        ImportFuzz.run(seeds: [seed], cases: 1_000, seed: 0x584D_4C54) { _ = try XMLTokens.tokens($0) }
    }
}
