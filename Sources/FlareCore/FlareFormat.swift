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

extension FormatError {
    /// The format-layer form of a model error, so loaders see only FormatError.
    init(_ error: ModelError) {
        switch error {
        case .invalidFill(let message), .invalidText(let message): self = .invalid(message)
        case .sceneNotFound, .layerNotFound, .layerLocked: self = .invalid("\(error)")
        }
    }
}

public enum FlareFormat {
    public static let formatName = "flare"
    public static let currentVersion = 1

    /// Largest input `decode` will parse: 64 MB.
    public static let maxFileBytes = 64 * 1024 * 1024
    /// Most layers allowed in any one scene or symbol.
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
        let symbolIDs = try validateHeaders(document)
        for scene in document.scenes {
            try validate(scene.layers, owner: "scene \(scene.id)", symbols: symbolIDs)
        }
        for symbol in document.symbols {
            try validate(symbol.layers, owner: "symbol \(symbol.id)", symbols: symbolIDs)
        }
        try checkSymbolCycles(document.symbols)
        try validateStateMachines(document)
    }

    /// Like `validate(_:)`, after a change to layer `layerID` of scene `sceneID`
    /// only (an edit, insert, removal or move) of `previous`, which was valid.
    /// Other layers are trusted, so the cost does not grow with the scene.
    static func validate(_ document: Document, layer layerID: String, scene sceneID: String,
                         since previous: Document) throws {
        let symbolIDs = try validateHeaders(document)
        guard let new = document.scenes.first(where: { $0.id == sceneID })?.layers,
              let old = previous.scenes.first(where: { $0.id == sceneID })?.layers else {
            return try validate(document)
        }
        if let i = new.firstIndex(where: { $0.id == layerID }) {
            let layer = new[i]
            try validate([layer], owner: "scene \(sceneID)", symbols: symbolIDs)
            let inserted = new.count > old.count
            // The other ids were unique before, so only a later copy of this one can clash.
            if inserted, new[(i + 1)...].contains(where: { $0.id == layerID }) {
                throw FormatError.invalid("scene \(sceneID): duplicate layer id \(layerID)")
            }
            let before = inserted ? nil
                : old.indices.contains(i) && old[i].id == layerID ? old[i] : old.first { $0.id == layerID }
            // The total was within the limits before, so only growth can break them.
            if new.count > maxLayersPerScene || pointCount(layer.shapes) > pointCount(before?.shapes ?? []) {
                try checkLimits(document)
            }
        }
        try checkSymbolCycles(document.symbols)
        try validateStateMachines(document)
    }

    /// Scene and symbol fields, without their layers. Returns the symbol ids.
    static func validateHeaders(_ document: Document) throws -> Set<String> {
        var sceneIDs = Set<String>()
        for scene in document.scenes {
            guard sceneIDs.insert(scene.id).inserted else { throw FormatError.invalid("duplicate scene id \(scene.id)") }
            guard scene.fps > 0 else { throw FormatError.invalid("scene \(scene.id): fps must be > 0") }
            guard scene.durationFrames >= 0 else { throw FormatError.invalid("scene \(scene.id): negative duration") }
            guard scene.width.isFinite, scene.width > 0, scene.height.isFinite, scene.height > 0 else {
                throw FormatError.invalid("scene \(scene.id): canvas size must be finite and > 0")
            }
            for (name, frame) in scene.labels where frame < 0 || frame > scene.durationFrames {
                throw FormatError.invalid("scene \(scene.id): label \(name) at frame \(frame) is outside the scene")
            }
        }
        var symbolIDs = Set<String>()
        for symbol in document.symbols {
            guard symbolIDs.insert(symbol.id).inserted else { throw FormatError.invalid("duplicate symbol id \(symbol.id)") }
            guard symbol.durationFrames >= 0 else { throw FormatError.invalid("symbol \(symbol.id): negative duration") }
        }
        return symbolIDs
    }

    /// Layer invariants shared by scenes and symbols. `owner` names the
    /// container in error messages, e.g. "scene s1". `symbols` holds the
    /// document's symbol ids, which instances must name.
    static func validate(_ layers: [Layer], owner: String, symbols: Set<String>) throws {
        try checkUniqueIDs(layers, owner: owner)
        for layer in layers {
            for shape in layer.shapes {
                do { try shape.fill.validate() } catch let error as ModelError { throw FormatError(error) }
                if let width = shape.stroke?.width, !(width.isFinite && width >= 0) {
                    throw FormatError.invalid("layer \(layer.id): stroke width must be finite and >= 0")
                }
                let points = shape.points + (shape.path?.elements.flatMap(\.points) ?? [])
                guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                    throw FormatError.invalid("layer \(layer.id): shape has a non-finite point")
                }
            }
            for text in layer.texts {
                do { try text.validate() } catch let error as ModelError { throw FormatError(error) }
            }
            for (property, track) in layer.tracks {
                guard !track.isEmpty else { throw FormatError.invalid("layer \(layer.id): empty track \(property)") }
                var previous = -1
                for k in track {
                    guard k.frame > previous else {
                        throw FormatError.invalid("layer \(layer.id): track \(property) not sorted or has duplicates")
                    }
                    previous = k.frame
                    guard k.value.isFinite else {
                        throw FormatError.invalid("layer \(layer.id): track \(property) has a non-finite value at frame \(k.frame)")
                    }
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

    static func checkUniqueIDs(_ layers: [Layer], owner: String) throws {
        var layerIDs = Set<String>()
        for layer in layers where !layerIDs.insert(layer.id).inserted {
            throw FormatError.invalid("\(owner): duplicate layer id \(layer.id)")
        }
    }

    /// Throws `tooLarge` if a scene or symbol has too many layers or the
    /// document too many points. Points are counted across scenes and symbols.
    static func checkLimits(_ document: Document) throws {
        let containers = document.scenes.map { ("scene \($0.id)", $0.layers) }
            + document.symbols.map { ("symbol \($0.id)", $0.layers) }
        var points = 0
        for (owner, layers) in containers {
            guard layers.count <= maxLayersPerScene else {
                throw FormatError.tooLarge("\(owner): \(layers.count) layers, limit \(maxLayersPerScene)")
            }
            for layer in layers {
                points += pointCount(layer.shapes)
                guard points <= maxTotalPoints else {
                    throw FormatError.tooLarge("more than \(maxTotalPoints) points")
                }
            }
        }
    }

    /// Points stored in `shapes`, counting path elements, for the size limit.
    static func pointCount(_ shapes: [Shape]) -> Int {
        var points = 0
        for shape in shapes {
            points += shape.points.count
            for element in shape.path?.elements ?? [] {
                points += element.pointCount
            }
        }
        return points
    }
}

extension PathElement {
    /// Points stored in this element, for the finite check.
    var points: [Point] {
        switch self {
        case .move(let to), .line(let to): [to]
        case .quad(let control, let to): [control, to]
        case .cubic(let control1, let control2, let to): [control1, control2, to]
        case .close: []
        }
    }

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
