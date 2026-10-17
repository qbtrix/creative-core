// RB-3: the CPU backend reproduces CoreRaster exactly. Every case compares
// with `==` against the direct CoreRaster call, never against a tolerance.
import CoreColor
import CoreRaster
import CoreRender
import Testing

/// A seeded buffer: the same seed always gives the same pixels.
private func seededBuffer(_ seed: UInt64, width: Int, height: Int) throws -> PixelBuffer {
    var state = seed
    func next() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(state >> 40) / Float(1 << 24)
    }
    var buffer = try PixelBuffer(width: width, height: height)
    for y in 0..<height {
        for x in 0..<width {
            try buffer.setPixel(x: x, y: y, RGBA(r: next(), g: next(), b: next(), a: next()))
        }
    }
    return buffer
}

@Test func cpuBackendReadBackEqualsInputForSeededBuffers() throws {
    let backend = CPUBackend()
    for seed in 0..<50 {
        let buffer = try seededBuffer(UInt64(seed), width: 1 + seed % 9, height: 1 + seed % 7)
        let surface = try backend.surface(buffer)
        #expect(try backend.read(surface) == buffer)
    }
}

@Test func cpuBackendDisplayMatchesCoreRasterInEachColorSpace() throws {
    let backend = CPUBackend()
    let buffer = try seededBuffer(3, width: 6, height: 4)
    let surface = try backend.surface(buffer)
    #expect(try backend.display(surface, colorSpace: .sRGB) == buffer.rgba8(colorSpace: .sRGB))
    #expect(try backend.display(surface, colorSpace: .displayP3) == buffer.rgba8(colorSpace: .displayP3))
}

@Test func cpuBackendCompositeMatchesCoreRasterForEveryBlendModeAndOffset() throws {
    let backend = CPUBackend()
    let source = try seededBuffer(7, width: 4, height: 3)
    let backdrop = try seededBuffer(9, width: 6, height: 5)
    // Offsets -1,-1 and 3,2 hang the source off the top-left and bottom-right edges.
    let offsets: [(x: Int, y: Int)] = [(-1, -1), (3, 2)]
    for mode in BlendMode.allCases {
        for opacity: Float in [0, 0.37, 1] {
            for offset in offsets {
                let expected = try CoreRaster.composite(source, onto: backdrop, x: offset.x, y: offset.y,
                                                       mode: mode, opacity: opacity)
                let sourceSurface = try backend.surface(source)
                var backdropSurface = try backend.surface(backdrop)
                try backend.composite(sourceSurface, onto: &backdropSurface, x: offset.x, y: offset.y,
                                      mode: mode, opacity: opacity)
                #expect(try backend.read(backdropSurface) == expected)
            }
        }
    }
}

@Test func cpuBackendReleasedSurfaceThrowsSurfaceMismatch() throws {
    let backend = CPUBackend()
    let surface = try backend.surface(try seededBuffer(1, width: 2, height: 2))
    backend.release(surface)
    #expect(throws: RenderError.surfaceMismatch) {
        try backend.read(surface)
    }
}

@Test func cpuBackendRefusesASurfaceFromAnotherBackend() throws {
    let backend = CPUBackend()
    let foreign = try FakeBackend(supports: []).surface(try seededBuffer(2, width: 2, height: 2))
    #expect(throws: RenderError.surfaceMismatch) {
        try backend.read(foreign)
    }
}

@Test func cpuBackendRunsOnlyDisplayAndCompositeUntilRB4() throws {
    let backend = CPUBackend()
    #expect(backend.supports == [.display, .composite])
    let surface = try backend.surface(try seededBuffer(4, width: 2, height: 2))
    #expect(throws: RenderError.unsupported(.blur)) {
        try backend.gaussianBlur(surface, sigma: 1)
    }
}
