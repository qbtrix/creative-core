// MaskFixtures.swift: seeded masks for the masks-mattes checks (MaskOpsTests,
// MaskCompositeTests), each a fixed formula or seeded SplitMix64.
@testable import CoreRaster

enum MaskFixtures {
    /// A 96 x 96 mask with the 64 px square at (16, 16) fully covered.
    static func square() throws -> Mask {
        try Mask.rectangle(width: 96, height: 96, x: 16, y: 16, w: 64, h: 64)
    }

    /// The ring's centre and radii: a disc of `outer` with a hole of `inner`.
    static let ringCenter = 32.0, ringOuter = 20.0, ringInner = 10.0

    /// A 64 x 64 ring centred at (32, 32), outer radius 20, inner radius 10.
    static func ring() throws -> Mask {
        var disc = try Mask.ellipse(width: 64, height: 64, centerX: ringCenter, centerY: ringCenter,
                                    radiusX: ringOuter, radiusY: ringOuter)
        try disc.subtract(Mask.ellipse(width: 64, height: 64, centerX: ringCenter, centerY: ringCenter,
                                       radiusX: ringInner, radiusY: ringInner))
        return disc
    }

    /// A 48 x 32 mask with an ellipse centred at (24, 16), radii 18 and 10.
    static func ellipse() throws -> Mask {
        try Mask.ellipse(width: 48, height: 32, centerX: 24, centerY: 16, radiusX: 18, radiusY: 10)
    }

    /// A mask with the given row-major coverage, top row first.
    static func values(width: Int, height: Int, _ values: [Float]) -> Mask {
        Mask(checkedWidth: width, height: height, storage: values)
    }

    /// A 2 x 2 saddle: `diagonal` top-left and bottom-right, `anti` on the other two.
    static func saddle(diagonal: Float, anti: Float) -> Mask {
        values(width: 2, height: 2, [diagonal, anti, anti, diagonal])
    }

    /// Seeded random coverage, about half of it exactly 0 or 1.
    static func random(width: Int, height: Int, _ rng: inout SplitMix64) -> Mask {
        let storage = (0..<(width * height)).map { _ -> Float in
            switch rng.next() % 4 {
            case 0: return 0
            case 1: return 1
            default: return .random(in: 0...1, using: &rng)
            }
        }
        return values(width: width, height: height, storage)
    }

    /// Every coverage value of `mask`, row-major.
    static func all(_ mask: Mask) throws -> [Float] {
        try (0..<mask.height).flatMap { y in try (0..<mask.width).map { x in try mask.coverage(x: x, y: y) } }
    }

    /// The signed shoelace area of a closed outline: positive when it runs
    /// counter-clockwise in the mask's coordinates.
    static func signedArea(_ ring: [Mask.Point]) -> Double {
        guard let last = ring.last else { return 0 }
        var sum = 0.0, previous = last
        for p in ring {
            sum += previous.x * p.y - p.x * previous.y
            previous = p
        }
        return sum / 2
    }
}
