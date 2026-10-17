// ParityPack.swift: how the checked-in CPU goldens are laid out, so any backend's tests can
// find one sample's golden. Goldens are packed: one golden per pack, filed as
// `<root>/<first op>/<ops joined by ->.rgba8`, a stack of bands top to bottom, one band per
// sample: the pack's ops in order, within an op its samples in `sampleSet(for:)` order. A band is
// as tall as that sample's result, and starts at the sum of the earlier bands' heights. Keep
// `ParityPack.all` and `resultHeight` in step with the goldens; CPUGoldenTests checks both.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One packed golden: the ops whose samples it stacks, and the tolerance it was cut with.
public struct ParityPack: Equatable, Sendable {
    /// The op the golden is filed under: the first of `ops`.
    public let op: RenderOp
    /// Every op in the pack, in band order; `op` first.
    public let ops: [RenderOp]
    /// The tolerance a result is compared to the golden with.
    public let tolerance: ParityTolerance

    private init(_ op: RenderOp, _ rest: RenderOp..., tolerance: ParityTolerance) {
        (self.op, ops, self.tolerance) = (op, [op] + rest, tolerance)
    }

    /// The checked-in packs, which cover every `RenderOp` once.
    public static let all = [
        ParityPack(.display, .blur, .adjust, .retouch, tolerance: .standard),
        ParityPack(.composite, .blendSeparable, tolerance: .standard),
        ParityPack(.blendNonSeparable, tolerance: .nonSeparable),
        ParityPack(.transform, tolerance: .standard),
        ParityPack(.resample, tolerance: .standard),
    ]

    /// The golden's file name: the ops' raw values joined by `-`.
    public var name: String { ops.map(\.rawValue).joined(separator: "-") }

    /// Each sample of the pack in band order, with the golden rows it fills.
    public func bands() throws -> [(op: RenderOp, sample: ParitySample, rows: Range<Int>)] {
        var top = 0
        return try ops.flatMap { op in
            try ParityHarness.sampleSet(for: op).map { sample in
                let h = Self.resultHeight(sample)
                defer { top += h }
                return (op, sample, top..<top + h)
            }
        }
    }

    /// The height of `sample`'s result: the backdrop's for a composite, the requested one for a
    /// resample, the source's width for a quarter or three-quarter turn, else the source's.
    private static func resultHeight(_ sample: ParitySample) -> Int {
        switch sample.call {
        case .composite: return sample.backdrop?.height ?? sample.source.height
        case let .resampled(_, height, _): return height
        case .rotated(.degrees90), .rotated(.degrees270): return sample.source.width
        case .rotated, .display, .gaussianBlur, .adjusted, .cloned: return sample.source.height
        }
    }

    /// Reads this pack's golden from `root` (see `ParityGolden.read(from:op:name:)`).
    public func read(from root: URL) throws -> ParityGolden {
        try ParityGolden.read(from: root, op: op, name: name)
    }
}

extension ParityGolden {
    /// Rows `rows` of this golden as a golden of their own, with the same width, color space and
    /// tolerance; the bytes are copied, never decoded. Throws `RenderError.raster` for an empty
    /// range or one outside the golden.
    public func rows(_ rows: Range<Int>) throws -> ParityGolden {
        guard !rows.isEmpty, rows.lowerBound >= 0, rows.upperBound <= header.height else {
            throw RenderError.raster("golden rows \(rows) are not inside its \(header.height) rows")
        }
        let rowBytes = header.width * 4
        let start = rows.lowerBound * rowBytes
        return ParityGolden(header: ParityGoldenHeader(width: header.width, height: rows.count,
                                                       colorSpace: header.colorSpace, tolerance: header.tolerance),
                            bytes: Array(bytes[start..<rows.upperBound * rowBytes]))
    }

    /// The golden of sample `sample` of `op`: its band of the pack that holds `op`, read from
    /// `root`. Compare a backend's `ParityHarness.render` of that sample with it through
    /// `ParityHarness.compare(golden:_:)`. Throws `RenderError.raster` when no pack holds `op`
    /// or `op` has no sample of that name.
    public static func band(from root: URL, op: RenderOp, sample: String) throws -> ParityGolden {
        guard let pack = ParityPack.all.first(where: { $0.ops.contains(op) }) else {
            throw RenderError.raster("no golden pack holds \(op.rawValue)")
        }
        guard let band = try pack.bands().first(where: { $0.op == op && $0.sample.name == sample }) else {
            throw RenderError.raster("\(op.rawValue) has no sample \"\(sample)\"")
        }
        return try pack.read(from: root).rows(band.rows)
    }

    private init(header: ParityGoldenHeader, bytes: [UInt8]) { (self.header, self.bytes) = (header, bytes) }
}
