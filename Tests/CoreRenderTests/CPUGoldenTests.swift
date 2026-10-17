// CPUGoldenTests.swift: the CPU goldens (render-backend RB-7). Every sample of
// `ParityHarness.sampleSet(for:)` for every op family, rendered on the CPU
// backend, is checked in under Golden/ as display bytes, and the CPU backend
// must reproduce each one with zero delta.
// Layout: one golden per pack below, filed as `Golden/<first op>/<ops>.rgba8`
// and `.json` (`ParityGolden.write`). A pack stacks its ops in order, each op's
// samples in `sampleSet` order, top to bottom; every sample of one op has the
// same size, and every op in a pack the same width, so sample k of an op is
// rows `start + k * height ..< start + (k + 1) * height`. Packing keeps the
// 67 samples in 5 goldens (10 files) instead of 134.
// Regenerate after an intended pixel change, then review the diff:
//   CORE_RENDER_WRITE_GOLDENS=1 swift test --filter CPUGoldenTests
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
        let fresh = try ParityGolden(stacked(samples.map(\.pixels)), tolerance: tolerance)
        let first = try #require(ops.first)
        let name = ops.map(\.rawValue).joined(separator: "-")
        if ProcessInfo.processInfo.environment["CORE_RENDER_WRITE_GOLDENS"] == "1" {
            try fresh.write(to: Self.root, op: first, name: name)
        }
        let golden = try ParityGolden.read(from: Self.root, op: first, name: name)
        try #require(golden.header == fresh.header, "\(name): \(golden.header) vs \(fresh.header)")
        // Zero delta is equal bytes: the compare (of the decoded bytes, which
        // drops the color of alpha-0 pixels) only locates a visible difference.
        let (want, got) = (try golden.buffer(), try fresh.buffer())
        var top = 0
        for sample in samples {
            let (w, h) = (sample.pixels.width, sample.pixels.height)
            let range = top * w * 4..<(top + h) * w * 4
            if golden.bytes[range] != fresh.bytes[range] {
                let result = try ParityHarness.compare(want.cropped(x: 0, y: top, width: w, height: h),
                                                       got.cropped(x: 0, y: top, width: w, height: h),
                                                       tolerance: ParityTolerance(bytes: 0, linear: 0))
                Issue.record("\(sample.op.rawValue)/\(sample.name) differs from its golden: \(result)")
            }
            top += h
        }
    }
}
