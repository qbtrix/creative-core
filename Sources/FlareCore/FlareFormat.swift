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
        case .invalidFill(let message), .invalidText(let message), .invalidStroke(let message): self = .invalid(message)
        case .sceneNotFound, .symbolNotFound, .layerNotFound, .layerLocked: self = .invalid("\(error)")
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
    /// Most masks on one layer.
    public static let maxMasksPerLayer = 32
    /// Most keys in one colour or shape track.
    public static let maxKeysPerTrack = 4_096
    /// Most colour and shape tracks, together, on one layer.
    public static let maxTracksPerLayer = 1_024

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
            for layer in scene.layers { try validateW1(layer, duration: scene.durationFrames) }
            try checkMattes(scene.layers, owner: "scene \(scene.id)")
        }
        for symbol in document.symbols {
            try validate(symbol.layers, owner: "symbol \(symbol.id)", symbols: symbolIDs)
            for layer in symbol.layers { try validateW1(layer, duration: symbol.durationFrames) }
            try checkMattes(symbol.layers, owner: "symbol \(symbol.id)")
        }
        try checkSymbolCycles(document.symbols)
        try validateStateMachines(document)
    }

    /// Like `validate(_:)`, after a change to layer `layerID` of `owner` only
    /// (an edit, insert, removal or move) of `previous`, which was valid.
    /// Other layers are trusted, so the cost does not grow with the scene.
    static func validate(_ document: Document, layer layerID: String, owner: LayerOwner,
                         since previous: Document) throws {
        let symbolIDs = try validateHeaders(document)
        guard let new = document.layers(of: owner), let old = previous.layers(of: owner),
              let duration = document.scenes.first(where: { owner == .scene($0.id) })?.durationFrames
                ?? document.symbols.first(where: { owner == .symbol($0.id) })?.durationFrames else {
            return try validate(document)
        }
        // Mattes name layers by id: only a removal or a change to this layer's matte can break one.
        var mattesChanged = new.count < old.count
        if let i = new.firstIndex(where: { $0.id == layerID }) {
            let layer = new[i]
            try validate([layer], owner: owner.description, symbols: symbolIDs)
            try validateW1(layer, duration: duration)
            let inserted = new.count > old.count
            // The other ids were unique before, so only a later copy of this one can clash.
            if inserted, new[(i + 1)...].contains(where: { $0.id == layerID }) {
                throw FormatError.invalid("\(owner): duplicate layer id \(layerID)")
            }
            let before = inserted ? nil
                : old.indices.contains(i) && old[i].id == layerID ? old[i] : old.first { $0.id == layerID }
            // The total was within the limits before, so only growth can break them.
            if new.count > maxLayersPerScene || pointCount(layer) > before.map(pointCount) ?? 0 {
                try checkLimits(document)
            }
            mattesChanged = mattesChanged || layer.matte != before?.matte
        }
        if mattesChanged { try checkMattes(new, owner: owner.description) }
        try checkSymbolCycles(document.symbols)
        try validateStateMachines(document)
    }

    /// Scene, symbol and swatch fields, without layers. Returns the symbol ids.
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
            guard scene.guides.allSatisfy({ $0.position.isFinite }) else {
                throw FormatError.invalid("scene \(scene.id): guide position must be finite")
            }
            guard scene.background.isFinite else {
                throw FormatError.invalid("scene \(scene.id): background color channels must be finite")
            }
        }
        var symbolIDs = Set<String>()
        for symbol in document.symbols {
            guard symbolIDs.insert(symbol.id).inserted else { throw FormatError.invalid("duplicate symbol id \(symbol.id)") }
            guard symbol.durationFrames >= 0 else { throw FormatError.invalid("symbol \(symbol.id): negative duration") }
        }
        var swatchNames = Set<String>()
        for swatch in document.swatches {
            guard !swatch.name.isEmpty else { throw FormatError.invalid("swatch name is empty") }
            guard swatchNames.insert(swatch.name).inserted else {
                throw FormatError.invalid("duplicate swatch name \(swatch.name)")
            }
            guard swatch.color.isInRange else {
                throw FormatError.invalid("swatch \(swatch.name): color channels must be finite and in 0...1")
            }
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
                do {
                    try shape.fill.validate()
                    try shape.stroke?.validate()
                } catch let error as ModelError { throw FormatError(error) }
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
                    // Lottie writes scale as a percent, so value × 100 must stay finite too.
                    guard !["scaleX", "scaleY"].contains(property) || (k.value * 100).isFinite else {
                        throw FormatError.invalid("layer \(layer.id): track \(property) value × 100 overflows at frame \(k.frame)")
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
                guard instance.transform.isFinite else {
                    throw FormatError.invalid("layer \(layer.id): instance transform must be finite")
                }
            }
        }
    }

    /// The W1Model.swift invariants of one layer that do not look at other layers.
    static func validateW1(_ layer: Layer, duration: Int) throws {
        func check(_ ok: Bool, _ what: @autoclosure () -> String) throws {
            guard ok else { throw FormatError.invalid("layer \(layer.id): \(what())") }
        }
        func finite(_ path: Path) -> Bool { path.elements.allSatisfy { $0.points.allSatisfy(\.isFinite) } }
        func checkKeys(_ frames: [Int], _ track: String) throws {
            try check(!frames.isEmpty && frames.count <= maxKeysPerTrack,
                      "track \(track) has \(frames.count) keys, allowed 1...\(maxKeysPerTrack)")
            for (k, frame) in frames.enumerated() {
                try check(frame >= 0 && frame <= duration, "track \(track) key \(k): frame \(frame) is outside 0...\(duration)")
                try check(k == 0 || frames[k - 1] < frame, "track \(track) key \(k): frame \(frame) is not after the key before it")
            }
        }
        // A layer with no W1 fields and no text has nothing below to check: skip the work.
        guard layer.hasW1Fields || !layer.texts.isEmpty else { return }
        try check(layer.masks.count <= maxMasksPerLayer, "\(layer.masks.count) masks, limit \(maxMasksPerLayer)")
        for (i, mask) in layer.masks.enumerated() {
            try check(finite(mask.path), "mask \(i): path has a non-finite point")
            try check(mask.feather.isFinite && mask.feather >= 0, "mask \(i): feather \(mask.feather) must be finite and >= 0")
            try check((0...1).contains(mask.opacity), "mask \(i): opacity \(mask.opacity) is outside 0...1")
        }
        for (t, text) in layer.texts.enumerated() {
            let count = text.runs.isEmpty ? 0 : text.string.count // graphemes, only read by runs
            var last = -1
            for (r, run) in text.runs.enumerated() {
                func at() -> String { "text \(t) run \(r)" } // built only for an error
                try check(run.length > 0, "\(at()): length \(run.length) must be > 0")
                try check(run.start > last, "\(at()): start \(run.start) is negative or overlaps the run before it")
                try check(run.start <= count - run.length, // last >= -1, so start >= 0
                          "\(at()): start \(run.start) + length \(run.length) passes the \(count) graphemes")
                last = run.start + run.length - 1
                try check(run.tracking?.isFinite ?? true, "\(at()): tracking must be finite")
                try check(run.baselineShift?.isFinite ?? true, "\(at()): baselineShift must be finite")
                try check(run.fontSize.map { $0.isFinite && $0 > 0 } ?? true,
                          "\(at()): fontSize \(run.fontSize ?? 0) must be finite and > 0")
                try check(run.weight.map { (100...900).contains($0) } ?? true,
                          "\(at()): weight \(run.weight ?? 0) is outside 100...900")
                do { try run.fill?.validate() } catch let error as ModelError { throw FormatError(error) }
            }
            if let p = text.paragraph {
                try check((0.5...4).contains(p.lineHeight), "text \(t): lineHeight \(p.lineHeight) is outside 0.5...4")
                try check(p.tracking.isFinite, "text \(t): paragraph tracking must be finite")
                try check(p.paragraphSpacing.isFinite, "text \(t): paragraphSpacing must be finite")
                try check(p.boxWidth.map { $0.isFinite && $0 > 0 } ?? true,
                          "text \(t): boxWidth \(p.boxWidth ?? 0) must be finite and > 0")
            }
            if let on = text.onPath {
                try check(finite(on.path), "text \(t): onPath path has a non-finite point")
                try check((0...1).contains(on.startOffset), // NaN fails too
                          "text \(t): onPath startOffset \(on.startOffset) is a fraction of the path length, 0...1")
            }
        }
        let tracks = layer.colorTracks.count + layer.shapeTracks.count
        try check(tracks <= maxTracksPerLayer, "\(tracks) colour and shape tracks, limit \(maxTracksPerLayer)")
        for (key, track) in layer.colorTracks {
            try check(colorTrackTargetExists(key, in: layer), "colour track key \(key) must be fill.<i> or stroke.<i> "
                      + "with i < \(layer.shapes.count) shapes, or text.<i> with i < \(layer.texts.count) texts")
            try checkKeys(track.map(\.frame), key)
            for (k, keyframe) in track.enumerated() {
                try check(keyframe.value.isInRange, "track \(key) key \(k): colour \(keyframe.value) has a channel outside 0...1")
            }
        }
        var animated = Set<Int>()
        for (s, track) in layer.shapeTracks.enumerated() {
            try check(layer.shapes.indices.contains(track.shapeIndex),
                      "shape track \(s): shapeIndex \(track.shapeIndex) is outside 0..<\(layer.shapes.count)")
            try check(animated.insert(track.shapeIndex).inserted, "shape track \(s): shape \(track.shapeIndex) already has a track")
            for (k, keyframe) in track.keys.enumerated() {
                try check(finite(keyframe.path), "shape track \(s) key \(k): path has a non-finite point")
            }
            try checkKeys(track.keys.map(\.frame), "shape \(track.shapeIndex)")
        }
    }

    /// Whether `key` is `fill.<i>` or `stroke.<i>` with `i` a shape index of
    /// `layer`, or `text.<i>` with `i` a text index, `i` written in plain decimal.
    static func colorTrackTargetExists(_ key: String, in layer: Layer) -> Bool {
        let parts = key.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let i = Int(parts[1]), String(i) == parts[1] else { return false }
        switch parts[0] {
        case "fill", "stroke": return layer.shapes.indices.contains(i)
        case "text": return layer.texts.indices.contains(i)
        default: return false
        }
    }

    /// Each matte names another layer of `layers`, and no chain of mattes
    /// returns to a layer it passed. Linear: a layer proven acyclic is not walked again.
    static func checkMattes(_ layers: [Layer], owner: String) throws {
        var source: [String: String] = [:]
        for layer in layers where layer.hasW1Fields { // no box, no matte
            if let matte = layer.matte { source[layer.id] = matte.sourceLayerID }
        }
        guard !source.isEmpty else { return }
        let ids = Set(layers.map(\.id))
        var acyclic = Set<String>()
        for (start, first) in source {
            guard first != start, ids.contains(first) else {
                throw FormatError.invalid("\(owner): layer \(start) matte source \(first) is not another layer here")
            }
            var seen: Set<String> = [start]
            var path = [start] // walk order, built beside `seen` for the error
            var next: String? = first
            while let id = next, !acyclic.contains(id) {
                path.append(id)
                guard seen.insert(id).inserted else {
                    let chain = path.joined(separator: " -> ")
                    throw FormatError.invalid("\(owner): mattes form a cycle \(chain); remove one layer's matte")
                }
                next = source[id]
            }
            acyclic.formUnion(seen)
        }
    }

    static func checkUniqueIDs(_ layers: [Layer], owner: String) throws {
        var layerIDs = Set<String>()
        for layer in layers where !layerIDs.insert(layer.id).inserted {
            throw FormatError.invalid("\(owner): duplicate layer id \(layer.id)")
        }
    }

    /// Throws `tooLarge` if a scene or symbol has too many layers or the
    /// document too many points. Points are counted across scenes and symbols,
    /// as `pointCount(_: Layer)` counts them.
    static func checkLimits(_ document: Document) throws {
        let containers = document.scenes.map { ("scene \($0.id)", $0.layers) }
            + document.symbols.map { ("symbol \($0.id)", $0.layers) }
        var points = 0
        for (owner, layers) in containers {
            guard layers.count <= maxLayersPerScene else {
                throw FormatError.tooLarge("\(owner): \(layers.count) layers, limit \(maxLayersPerScene)")
            }
            for layer in layers {
                points += pointCount(layer)
                guard points <= maxTotalPoints else {
                    throw FormatError.tooLarge("more than \(maxTotalPoints) points")
                }
            }
        }
    }

    /// Points stored in `layer` for the size limit: its shapes, mask paths,
    /// text-on-path paths and the path of every shape-track key.
    static func pointCount(_ layer: Layer) -> Int {
        guard layer.hasW1Fields || !layer.texts.isEmpty else { return pointCount(layer.shapes) }
        func count(_ path: Path) -> Int { path.elements.reduce(0) { $0 + $1.pointCount } }
        let masks = layer.masks.reduce(0) { $0 + count($1.path) }
        let onPaths = layer.texts.reduce(0) { $0 + ($1.onPath.map { count($0.path) } ?? 0) }
        let shapeKeys = layer.shapeTracks.reduce(0) { total, track in track.keys.reduce(total) { $0 + count($1.path) } }
        return pointCount(layer.shapes) + masks + onPaths + shapeKeys
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
}
