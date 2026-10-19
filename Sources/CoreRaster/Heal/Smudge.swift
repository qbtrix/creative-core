// Smudge.swift: the smudge brush's state, a carried colour dragged along
// successive dabs that fades by strength (retouch-heal RH-6). Each dab blends
// the carried patch onto the buffer by strength times coverage, then picks up
// what is now under the dab as the next carried patch, so the colour drags
// and fades. Dab positions off the buffer clip; nothing traps.

/// A smudge stroke in progress: the patch each dab carries to the next. Two
/// states are equal when they have the same strength and carry the same patch.
public struct SmudgeState: Hashable, Sendable {
    private let strength: Float
    /// The pixels under the last dab, row-major at its size; nil where the
    /// dab lay off the buffer. Nil before the first dab.
    private var carried: [RGBA?]?
    private var carriedWidth = 0
    private var carriedHeight = 0

    /// A new stroke. `strength` is in 0...1: how much of the carried colour
    /// each dab lays down; 0 changes nothing. `init` does not check it: a
    /// strength outside 0...1, or NaN, makes every `dab` on this state throw.
    public init(strength: Float) {
        self.strength = strength
    }

    /// Blends the carried patch onto `buffer` under `dab` (its top-left at
    /// `x`, `y`) by strength times coverage, then picks up what is now under
    /// the dab. The first dab of a stroke only picks up, and so does a dab
    /// whose mask size differs from the last dab's: it lays nothing and starts
    /// a new pick-up at its own size. Throws `RasterError.invalid` for a
    /// strength outside 0...1 or NaN.
    public mutating func dab(_ dab: Mask, x: Int, y: Int, on buffer: inout PixelBuffer) throws {
        try ColorMath.check("smudge strength", strength, in: 0...1)
        if strength > 0, let patch = carried, carriedWidth == dab.width, carriedHeight == dab.height {
            try lay(patch, through: dab, x: x, y: y, on: &buffer)
        }
        carried = try Self.pickUp(dab, x: x, y: y, from: buffer)
        carriedWidth = dab.width
        carriedHeight = dab.height
    }

    /// Blends each carried pixel onto the buffer pixel under it by strength
    /// times the dab's coverage there.
    private func lay(_ patch: [RGBA?], through dab: Mask, x: Int, y: Int, on buffer: inout PixelBuffer) throws {
        for j in 0..<dab.height {
            for i in 0..<dab.width {
                let k = j * dab.width + i
                guard let (bx, by) = Self.position(i, j, x: x, y: y, in: buffer), patch.indices.contains(k),
                      let source = patch[k] else { continue }
                let t = strength * (try dab.coverage(x: i, y: j))
                guard t > 0 else { continue }
                let p = try buffer.pixel(x: bx, y: by), u = 1 - t
                try buffer.setPixel(x: bx, y: by, RGBA(r: p.r * u + source.r * t, g: p.g * u + source.g * t,
                                                       b: p.b * u + source.b * t, a: p.a * u + source.a * t))
            }
        }
    }

    /// The buffer's pixels under the dab, nil where the dab lies off it.
    private static func pickUp(_ dab: Mask, x: Int, y: Int, from buffer: PixelBuffer) throws -> [RGBA?] {
        var patch = [RGBA?]()
        patch.reserveCapacity(dab.width * dab.height)
        for j in 0..<dab.height {
            for i in 0..<dab.width {
                if let (bx, by) = position(i, j, x: x, y: y, in: buffer) {
                    patch.append(try buffer.pixel(x: bx, y: by))
                } else {
                    patch.append(nil)
                }
            }
        }
        return patch
    }

    /// The buffer coordinate of dab pixel (`i`, `j`) placed at (`x`, `y`), or
    /// nil when it is off the buffer or the sum would overflow.
    private static func position(_ i: Int, _ j: Int, x: Int, y: Int, in buffer: PixelBuffer) -> (Int, Int)? {
        let (bx, overX) = x.addingReportingOverflow(i), (by, overY) = y.addingReportingOverflow(j)
        guard !overX, !overY, (0..<buffer.width).contains(bx), (0..<buffer.height).contains(by) else { return nil }
        return (bx, by)
    }
}
