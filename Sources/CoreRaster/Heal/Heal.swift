// Heal.swift: the true heal behind Photo's heal, spot heal and patch tools
// (retouch-heal RH-3, Photo blueprint CR-7). Texture from the buffer shifted
// by an offset is cloned through a mask and its colour solved so it meets the
// destination's edge with no seam (gradient-domain editing). Declared here by
// RH-0 as a stub; RH-3 fills in the body and never changes the signature.
//
// The solve works on the correction `h = f - g` (f the result, g the source):
// keeping g's gradients inside the mask means `Δh = 0` there, with
// `h = destination - source` on the ring just outside the mask. A neighbour
// off the buffer is dropped (no flux across the buffer's edge). Solving for h
// rather than f keeps a zero correction exactly zero, so a heal whose source
// is the destination returns it bit for bit.

extension PixelBuffer {
    /// The most pixels a heal's mask may cover; a mask covering more throws.
    public static let maxHealPixels = 4_000_000

    /// Successive over-relaxation factor for the heal's solve.
    static let healRelaxation = 1.9
    /// The solve stops once no correction moves by this much in a sweep.
    static let healTolerance = 1e-5
    /// The solve never runs more sweeps than this.
    static let healMaxSweeps = 500

    /// The buffer with the source (itself shifted by `offset`) cloned through
    /// `mask` and its colour solved to match the destination along the mask's
    /// edge. Only pixels inside the mask's bounds change. The mask must match
    /// the buffer's size and cover at most `maxHealPixels`; otherwise, or for
    /// an offset whose source lies off the buffer, it throws
    /// `RasterError.invalid`.
    public func healed(offset: (dx: Int, dy: Int), through mask: Mask) throws -> PixelBuffer {
        guard mask.width == width, mask.height == height else {
            throw RasterError.invalid("heal mask \(mask.width)x\(mask.height) differs from buffer \(width)x\(height)")
        }
        guard mask.area <= Double(Self.maxHealPixels) else {
            throw RasterError.invalid("heal mask covers \(mask.area) pixels: at most \(Self.maxHealPixels)")
        }
        guard let box = try Self.coveredBounds(of: mask) else { return self }
        try checkHealSource(box, offset: offset)
        let (dx, dy) = offset

        // The grid: the mask's bounds plus the one-pixel ring that holds the
        // boundary values, clipped to the buffer.
        let gx0 = max(box.minX - 1, 0), gx1 = min(box.maxX + 1, width - 1)
        let gy0 = max(box.minY - 1, 0), gy1 = min(box.maxY + 1, height - 1)
        let gw = gx1 - gx0 + 1, gh = gy1 - gy0 + 1
        var cover = [Float](repeating: 0, count: gw * gh)
        var h = [Double](repeating: 0, count: gw * gh * 4)
        for gy in 0..<gh {
            for gx in 0..<gw {
                let x = gx0 + gx, y = gy0 + gy, i = gy * gw + gx
                let c = try mask.coverage(x: x, y: y)
                cover[i] = c
                guard c == 0 else { continue }
                let dest = try pixel(x: x, y: y)
                let src = try pixel(x: min(max(x + dx, 0), width - 1), y: min(max(y + dy, 0), height - 1))
                let edge = Self.channelsOf(dest), from = Self.channelsOf(src)
                for k in 0..<4 { h[i * 4 + k] = Double(edge[k]) - Double(from[k]) }
            }
        }

        Self.relaxHeal(&h, cover: cover, width: gw, height: gh)

        var result = self
        for gy in 0..<gh {
            for gx in 0..<gw {
                let i = gy * gw + gx
                let c = cover[i]
                guard c > 0 else { continue }
                let x = gx0 + gx, y = gy0 + gy
                let src = Self.channelsOf(try pixel(x: x + dx, y: y + dy))
                let dest = Self.channelsOf(try pixel(x: x, y: y))
                var out = [Float](repeating: 0, count: 4)
                for k in 0..<4 {
                    let f = Float(Double(src[k]) + h[i * 4 + k])
                    out[k] = c >= 1 ? f : dest[k] + (f - dest[k]) * c
                }
                try result.setPixel(x: x, y: y, RGBA(r: out[0], g: out[1], b: out[2], a: out[3]))
            }
        }
        return result
    }

    /// The smallest rectangle holding every pixel `mask` covers, or nil for
    /// an empty mask.
    static func coveredBounds(of mask: Mask) throws -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var minX = mask.width, minY = mask.height, maxX = -1, maxY = -1
        for y in 0..<mask.height {
            for x in 0..<mask.width where try mask.coverage(x: x, y: y) > 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return (minX, minY, maxX, maxY)
    }

    /// Throws unless the source of every pixel in `box`, shifted by
    /// `offset`, lies on the buffer; overflow counts as off the buffer.
    func checkHealSource(_ box: (minX: Int, minY: Int, maxX: Int, maxY: Int), offset: (dx: Int, dy: Int)) throws {
        let left = box.minX.addingReportingOverflow(offset.dx), right = box.maxX.addingReportingOverflow(offset.dx)
        let top = box.minY.addingReportingOverflow(offset.dy), bottom = box.maxY.addingReportingOverflow(offset.dy)
        guard !left.overflow, !right.overflow, !top.overflow, !bottom.overflow,
              left.partialValue >= 0, right.partialValue < width,
              top.partialValue >= 0, bottom.partialValue < height else {
            throw RasterError.invalid("heal offset (\(offset.dx), \(offset.dy)) puts the source off the buffer")
        }
    }

    /// Solves `Δh = 0` for every covered cell of the grid by successive
    /// over-relaxation, holding uncovered cells fixed. Every loop is bounded
    /// by the grid and by `healMaxSweeps`.
    static func relaxHeal(_ h: inout [Double], cover: [Float], width gw: Int, height gh: Int) {
        var sweep = 0
        while sweep < healMaxSweeps {
            sweep += 1
            var largest = 0.0
            for gy in 0..<gh {
                for gx in 0..<gw where cover[gy * gw + gx] > 0 {
                    let i = gy * gw + gx
                    let left = gx > 0, right = gx < gw - 1, up = gy > 0, down = gy < gh - 1
                    let count = (left ? 1 : 0) + (right ? 1 : 0) + (up ? 1 : 0) + (down ? 1 : 0)
                    guard count > 0 else { continue }
                    for k in 0..<4 {
                        var sum = 0.0
                        if left { sum += h[(i - 1) * 4 + k] }
                        if right { sum += h[(i + 1) * 4 + k] }
                        if up { sum += h[(i - gw) * 4 + k] }
                        if down { sum += h[(i + gw) * 4 + k] }
                        let step = healRelaxation * (sum / Double(count) - h[i * 4 + k])
                        h[i * 4 + k] += step
                        largest = max(largest, abs(step))
                    }
                }
            }
            if largest < healTolerance { break }
        }
    }

    /// A pixel's four components in storage order.
    static func channelsOf(_ p: RGBA) -> [Float] { [p.r, p.g, p.b, p.a] }
}
