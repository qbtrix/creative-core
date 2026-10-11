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
}

public enum FlareFormat {
    public static let formatName = "flare"
    public static let currentVersion = 1

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
        var sceneIDs = Set<String>()
        for scene in document.scenes {
            guard sceneIDs.insert(scene.id).inserted else { throw FormatError.invalid("duplicate scene id \(scene.id)") }
            guard scene.fps > 0 else { throw FormatError.invalid("scene \(scene.id): fps must be > 0") }
            guard scene.durationFrames >= 0 else { throw FormatError.invalid("scene \(scene.id): negative duration") }
            guard scene.width.isFinite, scene.width > 0, scene.height.isFinite, scene.height > 0 else {
                throw FormatError.invalid("scene \(scene.id): canvas size must be finite and > 0")
            }
            var layerIDs = Set<String>()
            for layer in scene.layers {
                guard layerIDs.insert(layer.id).inserted else {
                    throw FormatError.invalid("scene \(scene.id): duplicate layer id \(layer.id)")
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
            }
        }
    }
}
