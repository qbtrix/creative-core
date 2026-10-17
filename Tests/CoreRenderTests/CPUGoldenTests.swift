// CPUGoldenTests.swift: the CPU goldens (render-backend RB-7). Every sample of
// `ParityHarness.sampleSet(for:)` for every op family, rendered on the CPU
// backend, is checked in under Golden/ as display bytes, and the CPU backend
// must reproduce each one with zero delta. Another backend checks its results
// against them with `ParityHarness.compare(golden:_:)`, in bytes.
// Layout: one golden per pack below, filed as `Golden/<first op>/<ops joined
// by ->.rgba8` and `.json` (`ParityGolden.write`), 67 samples in 5 goldens.
// A pack is a stack of bands, top to bottom, one band per sample: the pack's
// ops in order, and within an op its samples in `sampleSet(for:)` order. A band
// is as tall as that sample's CPU result, and band k starts at the sum of the
// earlier bands' heights (`bands(_:)`). Today every sample in a pack has one
// size, so band k is rows `k * h ..< (k + 1) * h`, h = header height / bands.
// For example display/display-blur-adjust-retouch is 9 wide with 20 bands of 7
// rows: display 0-3, blur 4-7, adjust 8-11, retouch 12-19 (the four sources
// random, alpha-zero, alpha-subnormal, opaque-rows, then off-left, off-top,
// off-right, off-bottom); so blur's alpha-zero is band 5, rows 35..<42.
// The goldens were cut on Linux x86_64 with
//   CORE_RENDER_WRITE_GOLDENS=1 swift test --filter CPUGoldenTests
// (rerun it after an intended pixel change, then review the diff). macOS may
// round one ulp differently, so the slice counts as verified only once the
// macOS job passes these goldens too.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreRaster
import CoreRender
import Testing

@Suite struct CPUGoldenTests {
    /// Each golden's ops, stacked in this order; the tolerance is the one a
    /// GPU result is compared to it with.
    static let packs: [(ops: [RenderOp], tolerance: ParityTolerance)] = [
        ([.display, .blur, .adjust, .retouch], .standard),
        ([.composite, .blendSeparable], .standard),
        ([.blendNonSeparable], .nonSeparable),
        ([.transform], .standard),
        ([.resample], .standard),
    ]

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Golden", isDirectory: true)

    /// Each sample of `ops`, rendered on a fresh CPU backend, with its op.
    private func rendered(_ ops: [RenderOp]) throws -> [(op: RenderOp, name: String, pixels: PixelBuffer)] {
        let cpu = CPUBackend()
        return try ops.flatMap { op in
            try ParityHarness.sampleSet(for: op).map { (op, $0.name, try ParityHarness.render($0, on: cpu)) }
        }
    }

    /// The rows of each band in a pack whose bands are `heights` tall, top to bottom.
    static func bands(_ heights: [Int]) -> [Range<Int>] {
        var top = 0
        return heights.map { h in
            defer { top += h }
            return top..<top + h
        }
    }

    @Test func bandsStartAtTheSumOfTheEarlierHeights() {
        #expect(Self.bands([7, 7, 5]) == [0..<7, 7..<14, 14..<19])
    }

    /// `parts` stacked top to bottom; every part must be `width` wide.
    private func stacked(_ parts: [PixelBuffer]) throws -> PixelBuffer {
        let width = parts.first?.width ?? 0
        var sheet = try PixelBuffer(width: width, height: parts.reduce(0) { $0 + $1.height })
        var top = 0
        for part in parts {
            try #require(part.width == width, "a pack mixes widths \(width) and \(part.width)")
            for y in 0..<part.height {
                for x in 0..<width { try sheet.setPixel(x: x, y: top + y, part.pixel(x: x, y: y)) }
            }
            top += part.height
        }
        return sheet
    }

    @Test func packsCoverEveryFamilyOnce() {
        #expect(Self.packs.flatMap(\.ops).sorted { $0.rawValue < $1.rawValue }
            == RenderOp.allCases.sorted { $0.rawValue < $1.rawValue })
    }

    @Test(arguments: packs.indices)
    func cpuReproducesGoldenWithZeroDelta(pack: Int) throws {
        let (ops, tolerance) = Self.packs[pack]
        let samples = try rendered(ops)
        let sheet = try stacked(samples.map(\.pixels))
        let fresh = try ParityGolden(sheet, tolerance: tolerance)
        let first = try #require(ops.first)
        let name = ops.map(\.rawValue).joined(separator: "-")
        if ProcessInfo.processInfo.environment["CORE_RENDER_WRITE_GOLDENS"] == "1" {
            try fresh.write(to: Self.root, op: first, name: name)
        }
        let golden = try ParityGolden.read(from: Self.root, op: first, name: name)
        try #require(golden.header == fresh.header, "\(name): \(golden.header) vs \(fresh.header)")
        #expect(try ParityHarness.compare(golden: golden, sheet).passed, "\(name)")
        // Zero delta is equal bytes: the compare (of the decoded bytes, which
        // drops the color of alpha-0 pixels) only locates a visible difference.
        let (want, got) = (try golden.buffer(), try fresh.buffer())
        for (sample, rows) in zip(samples, Self.bands(samples.map(\.pixels.height))) {
            let (w, h) = (sample.pixels.width, rows.count)
            let range = rows.lowerBound * w * 4..<rows.upperBound * w * 4
            if golden.bytes[range] != fresh.bytes[range] {
                let result = try ParityHarness.compare(want.cropped(x: 0, y: rows.lowerBound, width: w, height: h),
                                                       got.cropped(x: 0, y: rows.lowerBound, width: w, height: h),
                                                       tolerance: ParityTolerance(bytes: 0, linear: 0))
                Issue.record("\(sample.op.rawValue)/\(sample.name) differs from its golden: \(result)")
            }
        }
    }
}
