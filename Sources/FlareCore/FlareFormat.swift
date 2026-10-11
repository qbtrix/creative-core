// FlareFormat.swift: the .flare file format, version 1. JSON of the shape
//   {"document": {...}, "format": "flare", "version": 1}
//
// Invariants:
// - encode uses sorted keys, so encode(decode(encode(d))) is byte-identical
// - decode never crashes: every bad input throws a FormatError
// - unknown fields at any level are ignored (forward compatibility)
// - a file from a newer version throws unsupportedVersion rather than guessing
// - decoded documents pass validate() before they are returned
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum FormatError: Error, Equatable, Sendable {
    /// Not JSON, or JSON of the wrong shape.
    case malformed(String)
    /// Valid JSON, but `format` is missing or not "flare".
    case notAFlareFile
    case unsupportedVersion(Int)
    /// Parsed fine but breaks a document invariant.
    case invalid(String)
    /// Over one of the size limits in `FlareFormat` (bytes, layers or points).
    case tooLarge(String)
}

public enum FlareFormat {
    public static let formatName = "flare"
    public static let currentVersion = 1

    /// Largest input `decode` will parse: 64 MB.
    public static let maxFileBytes = 64 * 1024 * 1024
    /// Most layers allowed in any one scene.
    public static let maxLayersPerScene = 10_000
    /// Most points allowed in the whole document, counting `Shape.points` and
    /// the points of every path element.
    public static let maxTotalPoints = 1_000_000

    struct Header: Decodable {
        var format: String?
        var version: Int?
    }

    struct Envelope: Codable {
        var format: String
        var version: Int
        var document: Document
    }

    public static func encode(_ document: Document) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        do {
            return try encoder.encode(Envelope(format: formatName, version: currentVersion, document: document))
        } catch {
            throw FormatError.invalid("cannot encode: \(error)")
        }
    }

    public static func decode(_ data: Data) throws -> Document {
        guard data.count <= maxFileBytes else {
            throw FormatError.tooLarge("file is \(data.count) bytes, limit \(maxFileBytes)")
        }
        let decoder = JSONDecoder()
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw FormatError.malformed("not a JSON object")
        }
        guard header.format == formatName else { throw FormatError.notAFlareFile }
        guard let version = header.version else { throw FormatError.malformed("missing version") }
        guard version == currentVersion else { throw FormatError.unsupportedVersion(version) }
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw FormatError.malformed("bad document: \(error)")
        }
        try validate(envelope.document)
        return envelope.document
    }

    /// Checks the invariants listed in Document.swift.
    public static func validate(_ document: Document) throws {
        try checkLimits(document)
        var sceneIDs = Set<String>()
        for scene in document.scenes {
            guard sceneIDs.insert(scene.id).inserted else { throw FormatError.invalid("duplicate scene id \(scene.id)") }
            guard scene.fps > 0 else { throw FormatError.invalid("scene \(scene.id): fps must be > 0") }
            guard scene.durationFrames >= 0 else { throw FormatError.invalid("scene \(scene.id): negative duration") }
            guard scene.width.isFinite, scene.width > 0, scene.height.isFinite, scene.height > 0 else {
                throw FormatError.invalid("scene \(scene.id): canvas size must be finite and > 0")
            }
        }
        var symbolIDs = Set<String>()
        for symbol in document.symbols {
            guard symbolIDs.insert(symbol.id).inserted else { throw FormatError.invalid("duplicate symbol id \(symbol.id)") }
            guard symbol.durationFrames >= 0 else { throw FormatError.invalid("symbol \(symbol.id): negative duration") }
        }
        for scene in document.scenes {
            try validate(scene.layers, owner: "scene \(scene.id)", symbols: symbolIDs)
        }
        for symbol in document.symbols {
            try validate(symbol.layers, owner: "symbol \(symbol.id)", symbols: symbolIDs)
        }
        try checkSymbolCycles(document.symbols)
    }

    /// Layer invariants shared by scenes and symbols. `owner` names the
    /// container in error messages, e.g. "scene s1". `symbols` holds the
    /// document's symbol ids, which instances must name.
    static func validate(_ layers: [Layer], owner: String, symbols: Set<String>) throws {
        var layerIDs = Set<String>()
        for layer in layers {
            guard layerIDs.insert(layer.id).inserted else {
                throw FormatError.invalid("\(owner): duplicate layer id \(layer.id)")
            }
            for shape in layer.shapes {
                try shape.fill.validate()
                if let width = shape.stroke?.width, !(width.isFinite && width >= 0) {
                    throw FormatError.invalid("layer \(layer.id): stroke width must be finite and >= 0")
                }
            }
            for (property, track) in layer.tracks {
                guard !track.isEmpty else { throw FormatError.invalid("layer \(layer.id): empty track \(property)") }
                var previous = -1
                for k in track {
                    guard k.frame > previous else {
                        throw FormatError.invalid("layer \(layer.id): track \(property) not sorted or has duplicates")
                    }
                    previous = k.frame
                }
            }
            for instance in layer.instances {
                guard symbols.contains(instance.symbolID) else {
                    throw FormatError.invalid("layer \(layer.id): instance of unknown symbol \(instance.symbolID)")
                }
                guard instance.firstFrame >= 0 else {
                    throw FormatError.invalid("layer \(layer.id): instance firstFrame must be >= 0")
                }
            }
        }
    }

    /// Throws `tooLarge` if a scene has too many layers or the document too many points.
    static func checkLimits(_ document: Document) throws {
        var points = 0
        for scene in document.scenes {
            guard scene.layers.count <= maxLayersPerScene else {
                throw FormatError.tooLarge("scene \(scene.id): \(scene.layers.count) layers, limit \(maxLayersPerScene)")
            }
            for layer in scene.layers {
                for shape in layer.shapes {
                    points += shape.points.count
                    for element in shape.path?.elements ?? [] {
                        points += element.pointCount
                    }
                    guard points <= maxTotalPoints else {
                        throw FormatError.tooLarge("more than \(maxTotalPoints) points")
                    }
                }
            }
        }
    }
}

extension PathElement {
    /// Points stored in this element, for the size limit.
    var pointCount: Int {
        switch self {
        case .move, .line: 1
        case .quad: 2
        case .cubic: 3
        case .close: 0
        }
    }
}
