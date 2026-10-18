// CodecBudgetTests.swift: the layered-codecs release budgets (LC-9, quality
// row "Open a deep PSD"): opening a 100-layer 4000 x 3000 PSD takes at most
// 1.5 s with a peak resident size of at most 1.3 GB, and saving it at most 2 s.
// The fixture: 100 seeded 8-bit layers of 400 x 300 tiling the 12 MP canvas
// in a 10 x 10 grid, so the layers sum to one canvas of pixels, plus the
// merged image. 100 full-canvas layers would decode to 19 GB of the Float32
// pixels `PixelBuffer` holds (4.8 GB even as 8-bit), which no 1.3 GB budget
// can hold. Pixels are seeded noise, so PackBits finds no runs: the costliest
// RLE there is. G1 reuses `deepPSD()`.
// Debug builds skip the suite (the codecs' loops are many times slower there),
// so the gate never allocates the fixture; PSDReadTests, PSDWriteTests and
// CodecWalkTests carry the debug gate. Times are wall-clock medians of
// `runs`, each run's earlier result freed before the clock starts; each row
// prints `budget <row>: <ms> ms (budget <ms> ms)` and the thread CPU time, so
// a loaded machine's wait shows. Peak is the process's resident high-water
// mark during the first open: Linux resets it first (`/proc/self/clear_refs`),
// so it counts the runner and the file's bytes but nothing before the open;
// elsewhere it is the high-water mark since launch, an upper bound. Run the
// suite alone (`--filter CodecBudgetTests`) so no other suite's buffers count.
import CoreRaster
import Foundation
import Testing
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

private let runs = 3

private func milliseconds(_ d: Duration) -> String {
    let ms = Double(d.components.seconds) * 1e3 + Double(d.components.attoseconds) / 1e15
    return "\((ms * 1000).rounded() / 1000)"
}

/// Times `body` `runs` times, each after an untimed `free`; prints and gates
/// the wall-clock median, and prints the thread CPU median.
private func check(_ row: String, budget: Duration, free: () -> Void, _ body: () throws -> Void) throws {
    let clock = ContinuousClock()
    var wall: [Duration] = [], cpu: [Duration] = []
    for _ in 0..<runs {
        free()
        var spent = Duration.zero
        wall.append(try clock.measure { spent = try measureThreadCPUTime(body) })
        cpu.append(spent)
    }
    let median = wall.sorted()[runs / 2]
    print("budget \(row): \(milliseconds(median)) ms (budget \(milliseconds(budget)) ms; thread CPU \(milliseconds(cpu.sorted()[runs / 2])) ms)")
    #expect(median <= budget, "\(row): median \(median) over \(budget)")
}

/// The process's resident high-water mark, in bytes, and how far back it reaches.
private enum PeakMemory {
    /// Restarts the high-water mark at what is resident now. False where the
    /// platform cannot, so `bytes()` reaches back to launch.
    static func reset() -> Bool {
        #if os(Linux)
        let fd = open("/proc/self/clear_refs", O_WRONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return write(fd, "5", 1) == 1
        #else
        return false
        #endif
    }

    /// Linux's `VmHWM` (kilobytes), or Darwin's `ru_maxrss` (bytes there).
    static func bytes() -> Int? {
        #if os(Linux)
        guard let status = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8),
              let line = status.split(separator: "\n").first(where: { $0.hasPrefix("VmHWM:") }),
              let kb = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).dropFirst().first.flatMap({ Int($0) })
        else { return nil }
        return kb * 1024
        #else
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        return Int(usage.ru_maxrss)
        #endif
    }
}

/// Serialized, so no two 12 MP runs share cores, memory bandwidth or the peak.
@Suite(.serialized, .enabled(if: optimized, "12 MP timing needs an optimized build"))
struct CodecBudgetTests {
    static let width = 4000, height = 3000, columns = 10, rows = 10
    static let openBudget: Duration = .milliseconds(1500), saveBudget: Duration = .milliseconds(2000)
    static let peakBudget = 1_300_000_000

    /// The deep fixture's bytes, written by `PSD.write`; its pixels are freed on return.
    static func deepPSD() throws -> Data {
        var rng = SplitMix64(seed: 0x4C43_0009)
        let w = width / columns, h = height / rows
        let nodes: [LayerNode] = try (0..<rows * columns).map { i in
            var pixels = try PixelBuffer(width: w, height: h)
            for y in 0..<h {
                for x in 0..<w {
                    let p = RGBA(r: .random(in: 0...1, using: &rng), g: .random(in: 0...1, using: &rng),
                                 b: .random(in: 0...1, using: &rng), a: .random(in: 0.05...1, using: &rng))
                    try pixels.setPixel(x: x, y: y, p.premultiplied())
                }
            }
            return .pixels(PixelLayer(name: "Layer \(i)", pixels: pixels, x: i % columns * w, y: i / columns * h))
        }
        return try PSD.write(LayeredImage(width: width, height: height, nodes: nodes))
    }

    func checkShape(_ image: LayeredImage) {
        #expect(image.width == Self.width && image.height == Self.height && image.nodes.count == 100 && image.composite != nil)
        #expect(pixelLayer(image.nodes.last).map { $0.x == 3600 && $0.y == 2700 && $0.pixels.width == 400 } == true)
    }

    @Test func openDeep() throws {
        let data = try Self.deepPSD()
        let exact = PeakMemory.reset()
        var image = try PSD.read(data)
        let peak = try #require(PeakMemory.bytes())
        print("budget open deep PSD peak: \(peak / 1_000_000) MB (budget \(Self.peakBudget / 1_000_000) MB; \(exact ? "since the open" : "since launch"); file \(data.count / 1_000_000) MB)")
        #expect(peak <= Self.peakBudget, "open peak \(peak) bytes over \(Self.peakBudget)")
        checkShape(image)
        try check("open deep PSD 100 layers 12MP", budget: Self.openBudget,
                  free: { image = LayeredImage(width: 1, height: 1) }) {
            image = try PSD.read(data)
        }
        checkShape(image)
    }

    @Test func saveDeep() throws {
        let image = try PSD.read(Self.deepPSD())
        var saved = Data()
        try check("save deep PSD 100 layers 12MP", budget: Self.saveBudget, free: { saved = Data() }) {
            saved = try PSD.write(image)
        }
        #expect(try PSD.read(saved) == image)
    }
}
