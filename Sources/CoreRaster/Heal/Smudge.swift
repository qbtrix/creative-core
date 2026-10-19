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
    /// each dab lays down; 0 changes nothing. Throws `RasterError.invalid`
    /// for a strength outside 0...1 or NaN, so a bad pressure or slider value
    /// fails where the state is made, not mid-stroke.
    public init(strength: Float) throws {
        try ColorMath.check("smudge strength", strength, in: 0...1)
        self.strength = strength
    }

    /// Blends the carried patch onto `buffer` under `dab` (its top-left at
    /// `x`, `y`) by strength times coverage, then picks up what is now under
    /// the dab. The first dab of a stroke only picks up, and so does a dab
    /// whose mask size differs from the last dab's: it lays nothing and starts
    /// a new pick-up at its own size. Dab cells off the buffer are skipped.
    public mutating func dab(_ dab: Mask, x: Int, y: Int, on buffer: inout PixelBuffer) throws {
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
        guard let area = buffer.dabRect(dab, x: x, y: y) else { return }
        for by in area.rows {
            for bx in area.columns {
                let i = bx - x, j = by - y, k = j * dab.width + i
                guard patch.indices.contains(k), let source = patch[k] else { continue }
                let t = strength * (try dab.coverage(x: i, y: j))
                guard t > 0 else { continue }
                try buffer.setPixel(x: bx, y: by, try buffer.pixel(x: bx, y: by).mixed(toward: source, by: t))
            }
        }
    }

    /// The buffer's pixels under the dab, row-major at its size, nil where
    /// the dab lies off it.
    private static func pickUp(_ dab: Mask, x: Int, y: Int, from buffer: PixelBuffer) throws -> [RGBA?] {
        var patch = [RGBA?](repeating: nil, count: dab.width * dab.height)
        guard let area = buffer.dabRect(dab, x: x, y: y) else { return patch }
        for by in area.rows {
            for bx in area.columns {
                let k = (by - y) * dab.width + (bx - x)
                guard patch.indices.contains(k) else { continue }
                patch[k] = try buffer.pixel(x: bx, y: by)
            }
        }
        return patch
    }
}
