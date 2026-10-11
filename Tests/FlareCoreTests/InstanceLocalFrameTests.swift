// InstanceLocalFrameTests.swift: Instance.localFrame for each loop mode,
// as tables of parent frames, including symbol durations 0 and 1.
import FlareCore
import Testing

@Suite struct InstanceLocalFrameTests {
    struct Row: Sendable, CustomTestStringConvertible {
        var mode: Instance.LoopMode
        var firstFrame: Int
        var duration: Int
        var parent: Int
        var expected: Int
        var testDescription: String { "\(mode) first=\(firstFrame) d=\(duration) p=\(parent) -> \(expected)" }
    }

    static let rows: [Row] = [
        // loop wraps
        Row(mode: .loop, firstFrame: 0, duration: 4, parent: 0, expected: 0),
        Row(mode: .loop, firstFrame: 0, duration: 4, parent: 3, expected: 3),
        Row(mode: .loop, firstFrame: 0, duration: 4, parent: 4, expected: 0),
        Row(mode: .loop, firstFrame: 0, duration: 4, parent: 9, expected: 1),
        Row(mode: .loop, firstFrame: 2, duration: 4, parent: 0, expected: 2),
        Row(mode: .loop, firstFrame: 2, duration: 4, parent: 2, expected: 0),
        Row(mode: .loop, firstFrame: 0, duration: 4, parent: -1, expected: 3),
        Row(mode: .loop, firstFrame: 0, duration: 1, parent: 0, expected: 0),
        Row(mode: .loop, firstFrame: 0, duration: 1, parent: 7, expected: 0),
        Row(mode: .loop, firstFrame: 3, duration: 0, parent: 5, expected: 0),
        Row(mode: .loop, firstFrame: Int.max, duration: 4, parent: Int.max, expected: 2),
        // playOnce clamps
        Row(mode: .playOnce, firstFrame: 0, duration: 4, parent: 0, expected: 0),
        Row(mode: .playOnce, firstFrame: 0, duration: 4, parent: 3, expected: 3),
        Row(mode: .playOnce, firstFrame: 0, duration: 4, parent: 4, expected: 3),
        Row(mode: .playOnce, firstFrame: 0, duration: 4, parent: 100, expected: 3),
        Row(mode: .playOnce, firstFrame: 2, duration: 4, parent: 1, expected: 3),
        Row(mode: .playOnce, firstFrame: 0, duration: 4, parent: -2, expected: 0),
        Row(mode: .playOnce, firstFrame: 0, duration: 1, parent: 0, expected: 0),
        Row(mode: .playOnce, firstFrame: 0, duration: 1, parent: 5, expected: 0),
        Row(mode: .playOnce, firstFrame: 3, duration: 0, parent: 5, expected: 0),
        Row(mode: .playOnce, firstFrame: Int.max, duration: 4, parent: Int.max, expected: 3),
        Row(mode: .playOnce, firstFrame: 0, duration: 4, parent: Int.min, expected: 0),
        // singleFrame always shows firstFrame
        Row(mode: .singleFrame, firstFrame: 2, duration: 4, parent: 0, expected: 2),
        Row(mode: .singleFrame, firstFrame: 2, duration: 4, parent: 9, expected: 2),
        Row(mode: .singleFrame, firstFrame: 0, duration: 1, parent: 5, expected: 0),
        Row(mode: .singleFrame, firstFrame: 3, duration: 0, parent: 5, expected: 3),
    ]

    @Test(arguments: rows) func localFrame(row: Row) {
        let instance = Instance(symbolID: "s", firstFrame: row.firstFrame, loop: row.mode)
        #expect(instance.localFrame(parentFrame: row.parent, symbolDuration: row.duration) == row.expected)
    }

    @Test func seededInputsStayInRange() {
        var rng = SplitMix64(seed: 16)
        let modes: [Instance.LoopMode] = [.loop, .playOnce]
        for _ in 0..<2_000 {
            let duration = Int(rng.next() % 50)
            let instance = Instance(symbolID: "s", firstFrame: Int(bitPattern: UInt(rng.next())),
                                    loop: modes[Int(rng.next() % 2)])
            let frame = instance.localFrame(parentFrame: Int(bitPattern: UInt(rng.next())), symbolDuration: duration)
            #expect(frame >= 0 && frame < max(duration, 1))
        }
    }
}
