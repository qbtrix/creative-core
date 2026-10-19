// CPUGoldenTests.swift: the CPU goldens (render-backend RB-7). Every sample of
// `ParityHarness.sampleSet(for:)` for every op family, rendered on the CPU
// backend, is checked in under Golden/ as display bytes, and the CPU backend
// must reproduce each one with zero delta. Another backend checks its results
// against them with `ParityHarness.compare(golden:_:)`, in bytes.
// Layout: one golden per `ParityPack.all` entry, 121 samples in 7 goldens (affine/affine holds
// the 10 affine samples, all 9 wide; color/color the 44 colour samples, 11 cases on the four
// sources, each case's four in a row), as
// ParityPack.swift says; `ParityGolden.band(from:op:sample:)` cuts one sample's
// golden out of its pack. For example display/display-blur-adjust-retouch is 9
// wide with 20 bands of 7 rows: display 0-3, blur 4-7, adjust 8-11, retouch
// 12-19 (the four sources random, alpha-zero, alpha-subnormal, opaque-rows,
// then off-left, off-top, off-right, off-bottom); so blur's alpha-zero is band
// 5, rows 35..<42.
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
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Golden", isDirectory: true)

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
        // The CPU-first W1 families get packs when their features add samples.
        let ported = { (op: RenderOp) in !RenderOp.notOnMetalYet.contains(op) }
        #expect(ParityPack.all.flatMap(\.ops).filter(ported).sorted { $0.rawValue < $1.rawValue }
            == RenderOp.allCases.filter(ported).sorted { $0.rawValue < $1.rawValue })
    }

    @Test(arguments: ParityPack.all.indices)
    func cpuReproducesGoldenWithZeroDelta(pack index: Int) throws {
        let pack = ParityPack.all[index]
        let cpu = CPUBackend()
        let bands = try pack.bands()
        let results = try bands.map { try ParityHarness.render($0.sample, on: cpu) }
        let fresh = try ParityGolden(stacked(results), tolerance: pack.tolerance)
        if ProcessInfo.processInfo.environment["CORE_RENDER_WRITE_GOLDENS"] == "1" {
            try fresh.write(to: Self.root, op: pack.op, name: pack.name)
        }
        let golden = try pack.read(from: Self.root)
        try #require(golden.header == fresh.header, "\(pack.name): \(golden.header) vs \(fresh.header)")
        // Zero delta is equal bytes; the compare only locates the difference.
        for (band, result) in zip(bands, results) {
            let name = "\(band.op.rawValue)/\(band.sample.name)"
            #expect(result.height == band.rows.count, "\(name): band height")
            let want = try golden.rows(band.rows)
            if try want.bytes != fresh.rows(band.rows).bytes {
                Issue.record("\(name) differs from its golden: \(try ParityHarness.compare(golden: want, result))")
            }
        }
    }
}
