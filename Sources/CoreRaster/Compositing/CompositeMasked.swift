// CompositeMasked.swift: compositing through a mask in place. Each pixel's
// opacity is scaled by the mask's coverage at its offset, then blended by the
// one row blend in Composite.swift.
// Invariants: coverage outside the mask is 0; a row with no coverage above 0
// is never written, and a row covered fully takes the unmasked row exactly;
// offsets are compared before any subtraction, so no Int sum overflows.

extension PixelBuffer {
    /// Composites `src` over this buffer as `composite(_:x:y:mode:opacity:)`
    /// does, with each pixel's opacity scaled by `mask`, whose top-left pixel
    /// sits on this buffer's pixel (`maskX`, `maskY`), in the same coordinates
    /// as `x` and `y` (not relative to `src`); coverage outside the mask is 0, so
    /// those pixels are unchanged. The mask may hang off any edge. Same throws
    /// as the unmasked composite.
    public mutating func composite(_ src: PixelBuffer, x: Int, y: Int, mode: BlendMode, opacity: Float,
                                   mask: Mask, maskX: Int, maskY: Int) throws {
        try composite(src, x: x, y: y, mode: mode, opacity: opacity) { by, x0, count in
            guard maskY <= by, maskY > by - mask.height, maskX < x0 + count, maskX > x0 - mask.width else {
                return .skip
            }
            let row = (by - maskY) * mask.width - maskX
            var weights = [Float](repeating: 0, count: count)
            let from = max(maskX - x0, 0), to = min(maskX - x0 + mask.width, count)
            weights.replaceSubrange(from..<to, with: mask.storage[(row + x0 + from)..<(row + x0 + to)])
            guard weights.contains(where: { $0 > 0 }) else { return .skip }
            return weights.allSatisfy { $0 == 1 } ? .full : .partial(weights)
        }
    }
}
