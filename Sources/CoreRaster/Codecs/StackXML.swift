// StackXML.swift: a small bounded reader for OpenRaster's `stack.xml`, from
// the published OpenRaster spec. It keeps `image` (w, h), the root `stack`,
// nested `stack` and `layer` elements (name, src, x, y, opacity, visibility,
// composite-op) and skips every other element with all it holds.
// Invariants a reader must keep:
// - Nothing is trusted: the text is at most `maxBytes`; stacks nest at most
//   `OpenRaster.maxDepth` deep, the root stack the first, and any other
//   element at most one level below that (checked before each push onto an
//   explicit stack, never by recursion); there are at most
//   `OpenRaster.maxLayers` layers and nested stacks, the root stack not
//   counted; the canvas w and h are in
//   1...`OpenRaster.maxSide` and within `PixelBuffer.maxPixels`; x and y are
//   Ints within +-`maxOffset`, so summing them down the tree and adding a
//   layer's size cannot overflow; opacity must be finite (nan and inf throw)
//   and is clamped to 0...1; tags must balance. Breaking any of these throws
//   a `CodecError`.
// - Attribute values decode the five named entities and numeric references.
// - Children stay in file order, top first; OpenRaster.read reverses them.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The layer tree a `stack.xml` describes: the canvas size and the root
/// stack's children, top first.
struct StackXML: Equatable, Sendable {
    enum Node: Equatable, Sendable { case layer(Element), stack(Element, [Node]) }

    /// A `layer` or `stack`; `x` and `y` are relative to the parent stack.
    struct Element: Equatable, Sendable {
        var name: String, src: String?, x: Int, y: Int, opacity: Float, isHidden: Bool
        /// nil when the element has no `composite-op`.
        var blendMode: BlendMode?
    }

    var width: Int, height: Int
    var nodes: [Node]

    static let maxBytes = 16 << 20, maxOffset = 1 << 30
    static let blendModes: [String: BlendMode] = [
        "svg:src-over": .normal, "svg:multiply": .multiply, "svg:screen": .screen, "svg:overlay": .overlay,
        "svg:darken": .darken, "svg:lighten": .lighten, "svg:color-dodge": .colorDodge,
        "svg:color-burn": .colorBurn, "svg:hard-light": .hardLight, "svg:soft-light": .softLight,
        "svg:difference": .difference, "svg:exclusion": .exclusion, "svg:hue": .hue,
        "svg:saturation": .saturation, "svg:color": .color, "svg:luminosity": .luminosity,
        // The spec's additive op is linear dodge; it has no linear burn, so readers without this name use src-over.
        "svg:plus": .linearDodge, "afterglow:linear-burn": .linearBurn,
    ]

    private enum Kind { case image, stack, layer, skipped }
    private struct Frame { var name: String, kind: Kind, attributes: [String: String], children: [Node] = [] }

    static func parse(_ data: Data) throws -> StackXML {
        guard data.count <= maxBytes else { throw CodecError.tooLarge("stack.xml of \(data.count) bytes") }
        var scanner = Scanner(bytes: [UInt8](data))
        var open: [Frame] = [], result: StackXML?, count = 0
        while let tag = try scanner.nextTag() {
            switch tag {
            case .start(let name, let attributes, let closed):
                let kind: Kind
                switch (open.last?.kind, name) {
                case (nil, "image"):
                    guard result == nil else { throw CodecError.damaged("stack.xml has two images") }
                    kind = .image
                case (.image?, "stack"), (.stack?, "stack"): kind = .stack
                case (.stack?, "layer"): kind = .layer
                default: kind = .skipped
                }
                // open holds the image and every enclosing stack, so a stack pushed now is open.count deep.
                guard open.count <= OpenRaster.maxDepth + (kind == .stack ? 0 : 1) else {
                    throw CodecError.tooLarge("stack.xml stacks nested over \(OpenRaster.maxDepth) deep")
                }
                if kind == .layer || (kind == .stack && open.last?.kind == .stack) {
                    count += 1
                    guard count <= OpenRaster.maxLayers else {
                        throw CodecError.tooLarge("stack.xml over \(OpenRaster.maxLayers) layers and nested stacks")
                    }
                }
                open.append(Frame(name: name, kind: kind, attributes: attributes))
                if closed { try close(name, &open, &result) }
            case .end(let name):
                try close(name, &open, &result)
            }
        }
        if let frame = open.last { throw CodecError.damaged("stack.xml leaves <\(frame.name)> open") }
        guard let result else { throw CodecError.damaged("stack.xml has no image") }
        return result
    }

    private static func close(_ name: String, _ open: inout [Frame], _ result: inout StackXML?) throws {
        guard let frame = open.popLast(), frame.name == name else { throw CodecError.damaged("stack.xml closes </\(name)> early") }
        let node: Node
        switch frame.kind {
        case .skipped: return
        case .layer: node = .layer(try element(frame.attributes))
        case .stack: node = .stack(try element(frame.attributes), frame.children)
        case .image:
            guard frame.children.count == 1, case .stack(_, let nodes)? = frame.children.last else {
                throw CodecError.damaged("stack.xml image needs one root stack")
            }
            let width = try integer(frame.attributes, "w"), height = try integer(frame.attributes, "h")
            try OpenRaster.checkSize(width, height, "canvas")
            result = StackXML(width: width, height: height, nodes: nodes)
            return
        }
        open[open.count - 1].children.append(node)
    }

    private static func element(_ attributes: [String: String]) throws -> Element {
        var opacity: Float = 1
        if let text = attributes["opacity"] {
            guard let value = Float(text), value.isFinite else { throw CodecError.damaged("stack.xml opacity \(text)") }
            opacity = min(max(value, 0), 1)
        }
        // An unknown composite-op composites as src-over, as the spec asks.
        return Element(name: attributes["name"] ?? "", src: attributes["src"],
                       x: try integer(attributes, "x"), y: try integer(attributes, "y"), opacity: opacity,
                       isHidden: attributes["visibility"] == "hidden",
                       blendMode: attributes["composite-op"].map { blendModes[$0] ?? .normal })
    }

    /// The attribute as an integer within +-`maxOffset`; 0 when absent.
    private static func integer(_ attributes: [String: String], _ key: String) throws -> Int {
        guard let text = attributes[key] else { return 0 }
        guard let value = Int(text), value.magnitude <= UInt(maxOffset) else { throw CodecError.damaged("stack.xml \(key)=\(text)") }
        return value
    }
}

/// Splits XML text into start and end tags; text, comments, CDATA, processing
/// instructions and declarations are skipped.
private struct Scanner {
    enum Tag { case start(String, [String: String], closed: Bool), end(String) }
    let bytes: [UInt8]
    /// Always within 0...bytes.count.
    var at = 0

    mutating func nextTag() throws -> Tag? {
        while true {
            guard let open = bytes[at...].firstIndex(of: UInt8(ascii: "<")) else { return nil }
            at = open + 1
            if let (_, end) = [("?", "?>"), ("!--", "-->"), ("![CDATA[", "]]>"), ("!", ">")].first(where: { starts($0.0) }) {
                try skip(past: end)
                continue
            }
            if starts("/") { at += 1; let name = try self.name(); skipSpace(); try expect(">"); return .end(name) }
            let name = try self.name()
            var attributes: [String: String] = [:]
            while true {
                let spaced = skipSpace()
                if starts("/>") { at += 2; return .start(name, attributes, closed: true) }
                if starts(">") { at += 1; return .start(name, attributes, closed: false) }
                guard spaced else { throw CodecError.damaged("stack.xml attributes of <\(name)>") }
                let key = try self.name()
                skipSpace()
                try expect("=")
                skipSpace()
                guard at < bytes.count, bytes[at] == UInt8(ascii: "\"") || bytes[at] == UInt8(ascii: "'"),
                      let end = bytes[(at + 1)...].firstIndex(of: bytes[at]) else {
                    throw CodecError.damaged("stack.xml value of \(key)")
                }
                let value = try Self.decode(bytes[(at + 1)..<end])
                at = end + 1
                guard attributes.updateValue(value, forKey: key) == nil else { throw CodecError.damaged("stack.xml repeats \(key)") }
            }
        }
    }

    private func starts(_ text: String) -> Bool {
        let utf8 = Array(text.utf8)
        return bytes.count - at >= utf8.count && bytes[at..<(at + utf8.count)].elementsEqual(utf8)
    }

    private mutating func expect(_ text: String) throws {
        guard starts(text) else { throw CodecError.damaged("stack.xml expects \(text) at byte \(at)") }
        at += text.utf8.count
    }

    private mutating func skip(past text: String) throws {
        while at < bytes.count, !starts(text) { at += 1 }
        try expect(text)
    }

    @discardableResult private mutating func skipSpace() -> Bool {
        let start = at
        while at < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[at]) { at += 1 }
        return at > start
    }

    private mutating func name() throws -> String {
        let start = at
        while at < bytes.count, !Array(" \t\r\n/>=<\"'".utf8).contains(bytes[at]) { at += 1 }
        guard at > start else { throw CodecError.damaged("stack.xml expects a name at byte \(start)") }
        return String(decoding: bytes[start..<at], as: UTF8.self)
    }

    /// Replaces `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&#N;` and `&#xH;`.
    private static func decode(_ raw: ArraySlice<UInt8>) throws -> String {
        var out = "", rest = raw
        while let amp = rest.firstIndex(of: UInt8(ascii: "&")) {
            out += String(decoding: rest[..<amp], as: UTF8.self)
            guard let semi = rest[amp...].prefix(12).firstIndex(of: UInt8(ascii: ";")) else { throw CodecError.damaged("stack.xml entity") }
            let entity = String(decoding: rest[(amp + 1)..<semi], as: UTF8.self)
            let named: [String: Unicode.Scalar] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]
            let code = entity.hasPrefix("#x") ? UInt32(entity.dropFirst(2), radix: 16)
                : entity.hasPrefix("#") ? UInt32(entity.dropFirst(), radix: 10) : nil
            guard let scalar = named[entity] ?? code.flatMap(Unicode.Scalar.init), scalar.value != 0 else {
                throw CodecError.damaged("stack.xml entity &\(entity);")
            }
            out.unicodeScalars.append(scalar)
            rest = rest[(semi + 1)...]
        }
        return out + String(decoding: rest, as: UTF8.self)
    }
}
