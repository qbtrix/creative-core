// HealSolver.swift: the heal's Laplace solve, a geometric multigrid. A free
// cell solves `n·u − Σ neighbours = rhs` (n its neighbours on the grid); a
// fixed cell holds its value. Each V-cycle smooths with red-black Gauss-Seidel,
// solves the residual on a 2x coarser level and adds it back bilinearly. Every
// array is padded by a ring of zeros never written, so neighbour reads stay in.

struct HealSolver {
    struct Level {
        let width: Int, height: Int, stride: Int
        var u: [SIMD4<Float>], rhs: [SIMD4<Float>]
        /// `1 / n` for a free cell; 0 for a fixed cell or the pad.
        var inv: [Float]

        init(width: Int, height: Int) {
            (self.width, self.height, stride) = (width, height, width + 2)
            u = [SIMD4<Float>](repeating: .zero, count: (width + 2) * (height + 2))
            rhs = u
            inv = [Float](repeating: 0, count: u.count)
        }

        func index(_ x: Int, _ y: Int) -> Int { (y + 1) * stride + x + 1 }

        mutating func free(_ x: Int, _ y: Int) {
            let n = (x > 0 ? 1 : 0) + (x < width - 1 ? 1 : 0) + (y > 0 ? 1 : 0) + (y < height - 1 ? 1 : 0)
            inv[index(x, y)] = n > 0 ? 1 / Float(n) : 0
        }

        /// One red-black sweep; its largest step when `measured`, else 0.
        @discardableResult
        mutating func smooth(measured: Bool = false) -> Float {
            let width = width, height = height, s = stride
            var largest: Float = 0
            rhs.withUnsafeBufferPointer { rhs in
                inv.withUnsafeBufferPointer { inv in
                    u.withUnsafeMutableBufferPointer { u in
                        for colour in 0..<2 {
                            for y in 0..<height {
                                let row = (y + 1) * s + 1
                                for i in Swift.stride(from: row + (y + colour) & 1, to: row + width, by: 2) where inv[i] > 0 {
                                    let next = (rhs[i] + u[i - 1] + u[i + 1] + u[i - s] + u[i + s]) * inv[i]
                                    if measured { largest = max(largest, pointwiseMax(next - u[i], u[i] - next).max()) }
                                    u[i] = next
                                }
                            }
                        }
                    }
                }
            }
            return largest
        }
    }

    /// The grid, then each coarser level.
    private var levels: [Level]
    init(width: Int, height: Int) { levels = [Level(width: width, height: height)] }
    mutating func free(_ x: Int, _ y: Int) { levels[0].free(x, y) }
    mutating func fix(_ x: Int, _ y: Int, _ value: SIMD4<Float>) { levels[0].u[levels[0].index(x, y)] = value }
    /// Sets a free cell's right-hand side (0 until set).
    mutating func load(_ x: Int, _ y: Int, rhs: SIMD4<Float>) { levels[0].rhs[levels[0].index(x, y)] = rhs }
    func value(_ x: Int, _ y: Int) -> SIMD4<Float> { levels[0].u[levels[0].index(x, y)] }

    /// V-cycles until one's last sweep moves no cell by `tolerance`, at most
    /// `maxCycles`. A coarse cell is free only when all its children are.
    mutating func solve(tolerance: Float, maxCycles: Int) {
        while let fine = levels.last, max(fine.width, fine.height) > 4 {
            var coarse = Level(width: (fine.width + 1) / 2, height: (fine.height + 1) / 2)
            for y in 0..<coarse.height {
                for x in 0..<coarse.width { coarse.free(x, y) }
            }
            for y in 0..<fine.height {
                for x in 0..<fine.width where fine.inv[fine.index(x, y)] == 0 { coarse.inv[coarse.index(x / 2, y / 2)] = 0 }
            }
            levels.append(coarse)
        }
        for _ in 0..<maxCycles {
            if vCycle(0) < tolerance { break }
        }
    }

    private mutating func vCycle(_ l: Int) -> Float {
        guard l + 1 < levels.count else {
            for _ in 0..<63 { levels[l].smooth() }
            return levels[l].smooth(measured: true)
        }
        levels[l].smooth()
        levels[l].smooth()
        // Restrict: each free coarse cell's rhs is its children's summed residual.
        var coarse = levels[l + 1]
        coarse.u = [SIMD4<Float>](repeating: .zero, count: coarse.u.count)
        coarse.rhs = coarse.u
        let inv = levels[l].inv
        do { // u's copy ends here, so the prolong below writes u in place.
            let (u, rhs, s) = (levels[l].u, levels[l].rhs, levels[l].stride)
            for y in 0..<levels[l].height {
                for x in 0..<levels[l].width {
                    let i = levels[l].index(x, y), p = coarse.index(x / 2, y / 2)
                    guard inv[i] > 0, coarse.inv[p] > 0 else { continue }
                    let sum: SIMD4<Float> = rhs[i] + u[i - 1] + u[i + 1] + u[i - s] + u[i + s]
                    coarse.rhs[p] += sum - u[i] / inv[i]
                }
            }
        }
        levels[l + 1] = coarse
        _ = vCycle(l + 1)
        // Prolong: 9/16 of the parent, 3/16 of each side, 1/16 of the diagonal.
        let solved = levels[l + 1], fine = (width: levels[l].width, height: levels[l].height, stride: levels[l].stride)
        var u = levels[l].u
        levels[l].u = [] // u is now the only reference, so the writes below copy nothing.
        for y in 0..<fine.height {
            let py = y / 2, ny = min(max(py + (y & 1 == 0 ? -1 : 1), 0), solved.height - 1)
            for x in 0..<fine.width where inv[(y + 1) * fine.stride + x + 1] > 0 {
                let px = x / 2, nx = min(max(px + (x & 1 == 0 ? -1 : 1), 0), solved.width - 1)
                let parent: SIMD4<Float> = solved.u[solved.index(px, py)] * 9
                let sides: SIMD4<Float> = (solved.u[solved.index(nx, py)] + solved.u[solved.index(px, ny)]) * 3
                u[(y + 1) * fine.stride + x + 1] += (parent + sides + solved.u[solved.index(nx, ny)]) * (1 / 16)
            }
        }
        levels[l].u = u
        levels[l].smooth()
        return levels[l].smooth(measured: true)
    }
}
