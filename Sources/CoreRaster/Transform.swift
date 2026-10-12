// Transform.swift: exact pixel rearrangements of a PixelBuffer, cropping and
// quarter-turn rotation. Pixels are copied, never filtered, so every output
// component is one of the input's and the buffer invariants carry over.
// Invariant: a crop rectangle passes `validatedSize` and lies inside the buffer.

/// A clockwise rotation by a multiple of 90 degrees.
public enum QuarterTurn: Hashable, Sendable {
    case degrees90
    case degrees180
    case degrees270
}

extension PixelBuffer {
    /// The `width x height` region whose top-left pixel is at (`x`, `y`).
    /// Throws `RasterError.invalid` for a size `validatedSize` rejects or a
    /// rectangle that is not wholly inside this buffer.
    public func cropped(x: Int, y: Int, width newWidth: Int, height newHeight: Int) throws -> PixelBuffer {
        _ = try Self.validatedSize(width: newWidth, height: newHeight)
        guard x >= 0, y >= 0, newWidth <= width, newHeight <= height,
              x <= width - newWidth, y <= height - newHeight else {
            throw RasterError.invalid(
                "crop \(newWidth)x\(newHeight) at (\(x), \(y)) is outside \(width)x\(height)")
        }
        let input = components
        let c = Self.channels
        var output: [Float] = []
        output.reserveCapacity(newWidth * newHeight * c)
        for row in y..<(y + newHeight) {
            let start = (row * width + x) * c
            output.append(contentsOf: input[start..<(start + newWidth * c)])
        }
        return PixelBuffer(checkedWidth: newWidth, height: newHeight, storage: output)
    }

    /// This image turned clockwise by `turn`. A quarter turn swaps width and
    /// height.
    public func rotated(_ turn: QuarterTurn) -> PixelBuffer {
        let quarter = turn != .degrees180
        let newWidth = quarter ? height : width
        let newHeight = quarter ? width : height
        let input = components
        let c = Self.channels
        var output = [Float](repeating: 0, count: input.count)
        for ny in 0..<newHeight {
            for nx in 0..<newWidth {
                let (sx, sy) = switch turn {
                case .degrees90: (ny, height - 1 - nx)
                case .degrees180: (width - 1 - nx, height - 1 - ny)
                case .degrees270: (width - 1 - ny, nx)
                }
                let s = (sy * width + sx) * c
                let d = (ny * newWidth + nx) * c
                for k in 0..<c { output[d + k] = input[s + k] }
            }
        }
        return PixelBuffer(checkedWidth: newWidth, height: newHeight, storage: output)
    }
}
