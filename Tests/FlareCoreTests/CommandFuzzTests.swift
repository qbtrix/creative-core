// CommandFuzzTests.swift: seeded structured fuzz of every built-in command.
// Builds {"id", "params"} envelopes for every registered id, with params that
// are valid, plausible-but-wrong (ids and frames from a random document) or
// corrupted (wrong types, nulls, missing or extra keys, extreme numbers), then
// decodes them through the registry and performs them on a random document.
// Nothing crashes, every failure is a CommandError, a failed perform leaves
// the document untouched, and a successful one undoes exactly.
import FlareCore
import Foundation
import Testing

@Suite struct CommandFuzzTests {
    static let sceneIDs = ["s1", "s2", "s3"]
    static let layerIDs = ["ball", "bg", "l3"]
    static let props = ["x", "y", "opacity"]

    /// One params template per built-in id, from the registry samples.
    static func templates() throws -> [(id: String, params: [String: Any])] {
        try CommandRegistryTests.samples().map { cmd in
            let data = try CommandRegistry.builtIn.encode(cmd)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (type(of: cmd).id, object?["params"] as? [String: Any] ?? [:])
        }
    }

    /// A random document: up to 3 scenes, each with up to 3 layers (some locked,
    /// some hidden) holding random tracks and shapes. Ids are unique per level.
    static func randomDocument(_ rng: inout SplitMix64) -> Document {
        let scenes = sceneIDs.shuffled(using: &rng).prefix(Int.random(in: 0...3, using: &rng)).map { sid in
            let layers = layerIDs.shuffled(using: &rng).prefix(Int.random(in: 0...3, using: &rng)).map { lid in
                var tracks: [String: [Keyframe]] = [:]
                for p in props where Bool.random(using: &rng) {
                    let frames = Set((0..<Int.random(in: 1...4, using: &rng)).map { _ in
                        Int.random(in: -2...60, using: &rng)
                    })
                    tracks[p] = frames.sorted().map {
                        Keyframe(frame: $0, value: Double.random(in: -100...100, using: &rng),
                                 easing: Bool.random(using: &rng) ? .linear : .easeInOut)
                    }
                }
                let shapes = (0..<Int.random(in: 0...2, using: &rng)).map { _ in
                    Shape(points: [Point(x: 0, y: 0), Point(x: Double.random(in: 1...50, using: &rng), y: 3)])
                }
                return Layer(id: lid, name: lid.uppercased(), shapes: shapes, tracks: tracks,
                             isVisible: Bool.random(using: &rng), isLocked: Int.random(in: 0..<4, using: &rng) == 0)
            }
            return Scene(id: sid, name: sid, fps: Int.random(in: 1...60, using: &rng),
                         durationFrames: Int.random(in: 0...120, using: &rng), layers: Array(layers))
        }
        return Document(scenes: Array(scenes))
    }

    static func randomString(_ rng: inout SplitMix64) -> String {
        let pool = sceneIDs + layerIDs + props + ["", "missing", "💥", String(repeating: "z", count: 300), "linear"]
        return pool.randomElement(using: &rng) ?? ""
    }

    static func randomInt(_ rng: inout SplitMix64) -> Int {
        switch Int.random(in: 0..<4, using: &rng) {
        case 0: [Int.max, Int.min, Int.max - 1, Int.min + 1, -1, 0].randomElement(using: &rng) ?? 0
        case 1: Int.random(in: Int.min...Int.max, using: &rng)
        default: Int.random(in: -5...130, using: &rng)
        }
    }

    /// A value of any JSON type, mostly not what the field expects.
    static func garbage(_ rng: inout SplitMix64, depth: Int = 0) -> Any {
        switch Int.random(in: 0..<8, using: &rng) {
        case 0: return NSNull()
        case 1: return Bool.random(using: &rng)
        case 2: return randomInt(&rng)
        case 3: return [1e308, -1e308, 0.5, -0.0, 1e-300].randomElement(using: &rng) ?? 0.5
        case 4: return randomString(&rng)
        case 5 where depth < 2: return (0..<Int.random(in: 0...3, using: &rng)).map { _ in garbage(&rng, depth: depth + 1) }
        case 6 where depth < 2: return [randomString(&rng): garbage(&rng, depth: depth + 1)]
        default: return randomInt(&rng)
        }
    }

    /// Mutates `value` keeping its JSON shape most of the time: strings become
    /// other ids, numbers other numbers; sometimes the type itself is wrong.
    static func mutate(_ value: Any, _ rng: inout SplitMix64, depth: Int = 0) -> Any {
        if Int.random(in: 0..<10, using: &rng) == 0 { return garbage(&rng) }
        if let dict = value as? [String: Any] { return mutate(dict, &rng, depth: depth + 1) }
        if let array = value as? [Any] {
            var out = array.map { Bool.random(using: &rng) ? mutate($0, &rng, depth: depth + 1) : $0 }
            if !out.isEmpty, Int.random(in: 0..<4, using: &rng) == 0 { out.removeLast() }
            return out
        }
        if value is String { return randomString(&rng) }
        if let n = value as? NSNumber {
            // Integral values (frames, fps, indices) get ints; the rest doubles.
            if n.doubleValue.rounded() == n.doubleValue { return randomInt(&rng) }
            return Bool.random(using: &rng) ? Double.random(in: -2...2, using: &rng) : garbage(&rng)
        }
        return garbage(&rng)
    }

    static func mutate(_ params: [String: Any], _ rng: inout SplitMix64, depth: Int = 0) -> [String: Any] {
        var out = params
        for key in params.keys.sorted() {
            switch Int.random(in: 0..<10, using: &rng) {
            case 0: out[key] = nil
            case 1...4: if let v = params[key] { out[key] = mutate(v, &rng, depth: depth) }
            default: break
            }
        }
        if Int.random(in: 0..<8, using: &rng) == 0 { out[randomString(&rng)] = garbage(&rng) }
        return out
    }

    @Test func structuredFuzzNeverCrashesAndThrowsCleanly() throws {
        let templates = try Self.templates()
        #expect(Set(templates.map(\.id)) == CommandRegistryTests.expectedIDs)
        var rng = SplitMix64(seed: 38)
        var decoded = 0, performed = 0
        let clock = ContinuousClock()
        let start = clock.now
        for i in 0..<5000 {
            // Cycle through every id so each one gets its share of iterations.
            let template = templates[i % templates.count]
            let params = Int.random(in: 0..<6, using: &rng) == 0 ? template.params : Self.mutate(template.params, &rng)
            var envelope: [String: Any] = ["id": template.id, "params": params]
            if Int.random(in: 0..<50, using: &rng) == 0 { envelope["id"] = Self.randomString(&rng) }
            if Int.random(in: 0..<50, using: &rng) == 0 { envelope["params"] = Self.garbage(&rng) }
            let data = try JSONSerialization.data(withJSONObject: envelope)

            let command: any Command
            do {
                command = try CommandRegistry.builtIn.decode(data)
            } catch is CommandError {
                continue
            } catch {
                Issue.record("decode threw non-CommandError \(error) for \(String(decoding: data, as: UTF8.self))")
                continue
            }
            decoded += 1

            let document = Self.randomDocument(&rng)
            var engine = CommandEngine(document: document)
            do {
                try engine.perform(command)
            } catch is CommandError {
                #expect(engine.document == document, "failed \(template.id) mutated the document")
                #expect(!engine.canUndo)
                continue
            } catch {
                Issue.record("perform threw non-CommandError \(error) for \(template.id)")
                continue
            }
            performed += 1
            #expect(engine.canUndo)
            do {
                try engine.undo()
            } catch {
                Issue.record("undo of \(template.id) threw \(error)")
            }
            #expect(engine.document == document,
                    "undo of \(template.id) did not restore: \(String(decoding: data, as: UTF8.self))")
        }
        // The fuzz must reach both the decoders and the commands, not just bounce off.
        #expect(decoded > 1000)
        #expect(performed > 300)
        #expect(clock.now - start < .seconds(30), "fuzz too slow: \(clock.now - start)")
    }
}
