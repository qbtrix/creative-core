// XMLTokens.swift: a small, bounded XML tokenizer for the SVG reader.
//
// It reads UTF-8 bytes into start tags (with their attributes, in source
// order), end tags and text, following the XML 1.0 syntax for those parts
// only. Text and attribute values have the five predefined entities and
// numeric character references decoded. Comments, processing instructions,
// the XML declaration, DOCTYPE (with an internal subset) and CDATA sections
// are skipped. There are no namespaces and no DTD-defined entities.
//
// Untrusted input never crashes it: a broken tag, an unknown entity, a
// reference outside Unicode, a mismatched or unclosed element throws
// `ImportError.damaged`, and passing the byte, element or depth cap throws
// `ImportError.tooLarge`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One attribute of a start tag, its value with entities decoded.
public struct XMLAttribute: Sendable, Hashable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// One token of an XML document.
public enum XMLToken: Sendable, Hashable {
    /// `<name a="1">`, or `<name a="1"/>` when `selfClosing` (no `end` follows it).
    case start(name: String, attributes: [XMLAttribute], selfClosing: Bool)
    /// `</name>`.
    case end(String)
    /// Character data between tags, entities decoded; adjacent runs are joined.
    case text(String)
}

/// The bounded tokenizer.
public enum XMLTokens {
    /// The tokens of the XML in `data`. Throws `tooLarge` past `maxBytes`,
    /// `maxElements` start tags or `maxDepth` open elements, and `damaged` on
    /// malformed input.
    public static func tokens(
        _ data: Data,
        maxBytes: Int = SVGImport.maxBytes,
        maxElements: Int = SVGImport.maxElements,
        maxDepth: Int = SVGImport.maxDepth
    ) throws -> [XMLToken] {
        guard data.count <= maxBytes else { throw ImportError.tooLarge("XML is over \(maxBytes) bytes") }
        var reader = Reader(bytes: Array(data), maxElements: maxElements, maxDepth: maxDepth)
        return try reader.read()
    }

    static let commentEnd: [UInt8] = Array("-->".utf8)
    static let cdataEnd: [UInt8] = Array("]]>".utf8)
    static let piEnd: [UInt8] = Array("?>".utf8)

    /// The character an entity body (the text between `&` and `;`) stands for.
    static func entity(_ body: String) throws -> String {
        switch body {
        case "lt": return "<"
        case "gt": return ">"
        case "amp": return "&"
        case "quot": return "\""
        case "apos": return "'"
        default: break
        }
        var digits = Substring(body)
        guard digits.first == "#" else { throw ImportError.damaged("unknown entity &\(body);") }
        digits = digits.dropFirst()
        var radix = 10
        if digits.first == "x" || digits.first == "X" {
            radix = 16
            digits = digits.dropFirst()
        }
        // At most 8 digits, so the value fits in UInt32 before the range check.
        guard !digits.isEmpty, digits.count <= 8, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: radix),
              value != 0, let scalar = Unicode.Scalar(value)
        else { throw ImportError.damaged("bad character reference &\(body);") }
        return String(Character(scalar))
    }
}

private struct Reader {
    let bytes: [UInt8]
    let maxElements: Int
    let maxDepth: Int
    var at = 0
    var out: [XMLToken] = []
    var open: [String] = []
    var elements = 0

    init(bytes: [UInt8], maxElements: Int, maxDepth: Int) {
        self.bytes = bytes
        self.maxElements = maxElements
        self.maxDepth = maxDepth
    }

    func byte(_ offset: Int = 0) -> UInt8? {
        let i = at + offset
        return i >= 0 && i < bytes.count ? bytes[i] : nil
    }

    func starts(with pattern: String) -> Bool {
        let p = Array(pattern.utf8)
        return at + p.count <= bytes.count && bytes[at..<at + p.count].elementsEqual(p)
    }

    /// Moves past the next `pattern`, or throws naming `what` when it is missing.
    mutating func skip(past pattern: [UInt8], _ what: String) throws {
        guard !pattern.isEmpty, bytes.count >= pattern.count else { throw ImportError.damaged("unclosed \(what)") }
        var i = at
        while i + pattern.count <= bytes.count {
            if bytes[i..<i + pattern.count].elementsEqual(pattern) {
                at = i + pattern.count
                return
            }
            i += 1
        }
        throw ImportError.damaged("unclosed \(what) at \(at)")
    }

    mutating func read() throws -> [XMLToken] {
        var text: [UInt8] = []
        while let b = byte() {
            guard b == UInt8(ascii: "<") else {
                text.append(b)
                at += 1
                continue
            }
            if starts(with: "<!--") {
                at += 4
                try skip(past: XMLTokens.commentEnd, "comment")
            } else if starts(with: "<![CDATA[") {
                at += 9
                try skip(past: XMLTokens.cdataEnd, "CDATA section")
            } else if starts(with: "<?") {
                at += 2
                try skip(past: XMLTokens.piEnd, "processing instruction")
            } else if starts(with: "<!") {
                try skipDeclaration()
            } else {
                try flush(&text)
                if byte(1) == UInt8(ascii: "/") { try endTag() } else { try startTag() }
            }
        }
        try flush(&text)
        if let name = open.last { throw ImportError.damaged("unclosed <\(name)>") }
        return out
    }

    mutating func flush(_ text: inout [UInt8]) throws {
        guard !text.isEmpty else { return }
        let decoded = try decode(text)
        text.removeAll(keepingCapacity: true)
        if case .text(let previous)? = out.last {
            out[out.count - 1] = .text(previous + decoded)
        } else {
            out.append(.text(decoded))
        }
    }

    /// `<!DOCTYPE …>` and other declarations, with any `[…]` internal subset and quoted strings.
    mutating func skipDeclaration() throws {
        let start = at
        var brackets = 0
        var quote: UInt8?
        at += 2
        while let b = byte() {
            at += 1
            if let q = quote {
                if b == q { quote = nil }
            } else if b == UInt8(ascii: "\"") || b == UInt8(ascii: "'") {
                quote = b
            } else if b == UInt8(ascii: "[") {
                brackets += 1
            } else if b == UInt8(ascii: "]") {
                brackets -= 1
            } else if b == UInt8(ascii: ">") && brackets <= 0 {
                return
            }
        }
        throw ImportError.damaged("unclosed declaration at \(start)")
    }

    static func isSpace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D
    }

    static func isNameByte(_ b: UInt8) -> Bool {
        !isSpace(b) && !"<>/=\"'&".utf8.contains(b)
    }

    mutating func skipSpace() {
        while let b = byte(), Reader.isSpace(b) { at += 1 }
    }

    mutating func name() throws -> String {
        let start = at
        while let b = byte(), Reader.isNameByte(b) { at += 1 }
        guard at > start else { throw ImportError.damaged("missing name at \(start)") }
        return String(decoding: bytes[start..<at], as: UTF8.self)
    }

    mutating func endTag() throws {
        at += 2
        let tag = try name()
        skipSpace()
        guard byte() == UInt8(ascii: ">") else { throw ImportError.damaged("unclosed </\(tag)> at \(at)") }
        at += 1
        guard open.last == tag else { throw ImportError.damaged("</\(tag)> does not close <\(open.last ?? "")>") }
        open.removeLast()
        out.append(.end(tag))
    }

    mutating func startTag() throws {
        at += 1
        let tag = try name()
        var attributes: [XMLAttribute] = []
        while true {
            let spaced = byte().map(Reader.isSpace) ?? false
            skipSpace()
            guard let b = byte() else { throw ImportError.damaged("unclosed <\(tag)>") }
            if b == UInt8(ascii: ">") || (b == UInt8(ascii: "/") && byte(1) == UInt8(ascii: ">")) {
                let selfClosing = b == UInt8(ascii: "/")
                at += selfClosing ? 2 : 1
                try opened(tag, attributes, selfClosing: selfClosing)
                return
            }
            guard spaced else { throw ImportError.damaged("expected space before attribute at \(at)") }
            let key = try name()
            skipSpace()
            guard byte() == UInt8(ascii: "=") else { throw ImportError.damaged("attribute \(key) has no value") }
            at += 1
            skipSpace()
            let value = try quoted()
            guard !attributes.contains(where: { $0.name == key }) else {
                throw ImportError.damaged("duplicate attribute \(key) on <\(tag)>")
            }
            attributes.append(XMLAttribute(name: key, value: value))
        }
    }

    mutating func opened(_ tag: String, _ attributes: [XMLAttribute], selfClosing: Bool) throws {
        elements += 1
        guard elements <= maxElements else { throw ImportError.tooLarge("more than \(maxElements) elements") }
        let depth = open.count + 1
        if depth > maxDepth { throw ImportError.tooLarge("nesting deeper than \(maxDepth)") }
        out.append(.start(name: tag, attributes: attributes, selfClosing: selfClosing))
        if !selfClosing { open.append(tag) }
    }

    mutating func quoted() throws -> String {
        guard let q = byte(), q == UInt8(ascii: "\"") || q == UInt8(ascii: "'") else {
            throw ImportError.damaged("unquoted attribute value at \(at)")
        }
        at += 1
        let start = at
        while let b = byte(), b != q {
            guard b != UInt8(ascii: "<") else { throw ImportError.damaged("< in attribute value at \(at)") }
            at += 1
        }
        guard byte() == q else { throw ImportError.damaged("unclosed attribute value at \(start)") }
        let raw = Array(bytes[start..<at])
        at += 1
        return try decode(raw)
    }

    /// `raw` as UTF-8 with its entity and character references replaced.
    func decode(_ raw: [UInt8]) throws -> String {
        guard raw.contains(UInt8(ascii: "&")) else { return String(decoding: raw, as: UTF8.self) }
        var result = ""
        var i = 0
        var run = 0
        while i < raw.count {
            guard raw[i] == UInt8(ascii: "&") else {
                i += 1
                continue
            }
            result += String(decoding: raw[run..<i], as: UTF8.self)
            guard let semi = raw[i...].prefix(12).firstIndex(of: UInt8(ascii: ";")) else {
                throw ImportError.damaged("unterminated entity")
            }
            result += try XMLTokens.entity(String(decoding: raw[(i + 1)..<semi], as: UTF8.self))
            i = semi + 1
            run = i
        }
        result += String(decoding: raw[run..<raw.count], as: UTF8.self)
        return result
    }
}
