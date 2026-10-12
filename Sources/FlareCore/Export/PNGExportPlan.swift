// PNGExportPlan.swift: the plan for exporting a scene as numbered PNG frames.
//
// Pure planning, no rendering: one entry per exported frame with its frame
// number, its time in seconds (`Timeline.time(ofFrame:fps:)`), its pixel size
// (scene size times scale, rounded to nearest) and its file name
// ("frame_0000.png", zero-padded to at least 4 digits). A renderer consumes
// the plan later. Every input is checked before the plan is built, so bad
// scenes or parameters throw `PNGExportError` and never trap: frames are
// computed as `lower + i * step` with `i * step <= upper - lower`, and pixel
// sizes are compared against `maxPixels` while still Double.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum PNGExportError: Error, Equatable, Sendable {
    case invalidFPS(Int)
    /// The range leaves `0...durationFrames`.
    case frameOutOfRange(ClosedRange<Int>)
    case invalidStep(Int)
    /// Scale is not finite or not positive.
    case invalidScale(Double)
    /// Scaled size is not finite, under one pixel, or over `maxPixels` on a side.
    case invalidSize(width: Double, height: Double)
    /// The plan would hold more than `maxFrames` entries.
    case tooManyFrames(Int)
}

public struct PNGFramePlan: Sendable, Hashable {
    public var frame: Int
    public var time: Double
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var fileName: String
}

public enum PNGExportPlan {
    /// Largest pixel width or height of a planned frame.
    public static let maxPixels = 1 << 20
    /// Largest number of frames in one plan.
    public static let maxFrames = 1_000_000

    public static func plan(scene: Scene, frames: ClosedRange<Int>, scale: Double, step: Int = 1) throws -> [PNGFramePlan] {
        guard scene.fps > 0 else { throw PNGExportError.invalidFPS(scene.fps) }
        guard frames.lowerBound >= 0, frames.upperBound <= scene.durationFrames else {
            throw PNGExportError.frameOutOfRange(frames)
        }
        guard step > 0 else { throw PNGExportError.invalidStep(step) }
        guard scale.isFinite, scale > 0 else { throw PNGExportError.invalidScale(scale) }
        let width = (scene.width * scale).rounded()
        let height = (scene.height * scale).rounded()
        let limit = Double(maxPixels)
        guard width >= 1, height >= 1, width <= limit, height <= limit else {
            throw PNGExportError.invalidSize(width: width, height: height)  // NaN fails >= too
        }
        // lowerBound >= 0, so the span cannot overflow.
        let count = (frames.upperBound - frames.lowerBound) / step + 1
        guard count <= maxFrames else { throw PNGExportError.tooManyFrames(count) }
        return try (0..<count).map { i in
            let frame = frames.lowerBound + i * step
            return PNGFramePlan(
                frame: frame, time: try Timeline.time(ofFrame: frame, fps: scene.fps),
                pixelWidth: Int(width), pixelHeight: Int(height), fileName: fileName(frame: frame)
            )
        }
    }

    /// "frame_" + frame zero-padded to at least 4 digits + ".png"; frame >= 0.
    static func fileName(frame: Int) -> String {
        let digits = String(frame)
        return "frame_" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits + ".png"
    }
}
