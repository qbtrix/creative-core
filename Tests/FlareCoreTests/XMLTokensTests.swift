import Foundation
import Testing
@testable import FlareCore

/// The bounded XML tokenizer (VI-3), checked through a neutral token shape.
struct XMLTokensTests {
    enum Token: Equatable { case start(String, [String: String], selfClosing: Bool), end(String), text(String) }

    /// VI-3 replaces this body with a call to `XMLTokens`, mapping its tokens to `Token`.
    func tokens(_ xml: String) throws -> [Token] { throw ImportError.unsupported("XMLTokens not built") }
    func open(_ name: String, _ attributes: [String: String] = [:]) -> Token { .start(name, attributes, selfClosing: false) }
    func empty(_ name: String, _ attributes: [String: String] = [:]) -> Token { .start(name, attributes, selfClosing: true) }

    /// Tags, text and self-closing tags; attributes in both quote styles; CDATA and declarations skipped.
    @Test(.disabled("waits on VI-3")) func tagsAttributesAndDeclarations() throws {
        #expect(try tokens("<a><b>hi</b><c/></a>") == [open("a"), open("b"), .text("hi"), .end("b"), empty("c"), .end("a")])
        #expect(try tokens("<p x=\"1\" y='two words' z = \"a'b\"/>") == [empty("p", ["x": "1", "y": "two words", "z": "a'b"])])
        #expect(try tokens("<?xml version=\"1.0\"?><a><![CDATA[<b/>]]></a>") == [open("a"), .end("a")])
    }

    @Test(.disabled("waits on VI-3")) func skipsComments() throws {
        #expect(try tokens("<a><!-- a -> b --><b/></a>") == [open("a"), empty("b"), .end("a")])
    }

    @Test(.disabled("waits on VI-3")) func decodesEntities() throws {
        #expect(try tokens("<a t=\"&quot;&apos;\">&lt;&gt;&amp;&quot;&apos;&#65;&#x42;</a>") == [open("a", ["t": "\"'"]), .text("<>&\"'AB"), .end("a")])
    }

    @Test(.disabled("waits on VI-3")) func damagedInputThrows() {
        for xml in ["<a", "<a b=\"1></a>", "<a>&bogus;</a>", "<a>&#xZZ;</a>"] { #expect(throws: ImportError.self, "\(xml)") { _ = try tokens(xml) } }
    }

    @Test(.disabled("waits on VI-3")) func depthCapped() throws {
        func nested(_ n: Int) -> String { String(repeating: "<g>", count: n) + String(repeating: "</g>", count: n) }
        #expect(try tokens(nested(SVGImport.maxDepth)).count == 2 * SVGImport.maxDepth)
        #expect(throws: ImportError.self) { _ = try tokens(nested(SVGImport.maxDepth + 1)) }
    }
}
