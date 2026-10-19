// AffineWalkTests.swift: KJ-AC, the affine-composite key journey (AC-8), end
// to end on the CPU backend: a 3000 x 2000 photo layer scaled 0.5, rotated
// 30 degrees about its centre and moved (40, 25), composited through the
// matrix onto a 4000 x 3000 white backdrop, equals transform-then-composite
// within 1/255 and changes only the rotated bounds' rows (and columns),
// widened by bilinear's reach; flipped twice on either axis is the input; the
// canvas padded to 5000 x 3000 at `.right` keeps the image's right edge at
// x 5000; a 1920 x 1080 footage frame placed at 0.25 scale with bilinear
// lands in its 480 x 270 box and equals transform-then-composite too.
// Pixels are compared through `components`, not `pixel(x:y:)`, so the debug
// run in `scripts/ci` stays a few seconds.
import CoreRaster
import CoreRender
import Testing
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

@Suite struct AffineWalkTests {
    let cpu = CPUBackend()
    static let white = RGBA(r: 1, g: 1, b: 1, a: 1)

    /// An opaque `width` x `height` photo of seeded `block`-pixel sRGB tiles,
    /// built a row of bytes at a time.
    static func photo(width: Int, height: Int, block: Int, seed: UInt64) throws -> PixelBuffer {
        var rng = SplitMix64(seed: seed)
        let cols = (width + block - 1) / block, rows = (height + block - 1) / block
        let tiles = (0..<(cols * rows)).map { _ in
            [UInt8(truncatingIfNeeded: rng.next()), UInt8(truncatingIfNeeded: rng.next()),
             UInt8(truncatingIfNeeded: rng.next()), 255]
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 4)
        for tileRow in 0..<rows {
            var line: [UInt8] = []
            line.reserveCapacity(width * 4)
            for x in 0..<width { line += tiles[tileRow * cols + x / block] }
            for _ in 0..<min(block, height - tileRow * block) { bytes += line }
        }
        return try PixelBuffer(rgba8: bytes, width: width, height: height)
    }

    /// Scale `s`, rotate `degrees` clockwise (y down) about the centre of a
    /// `width` x `height` layer, then move by (`dx`, `dy`).
    static func placement(width: Int, height: Int, scale s: Double, degrees: Double, dx: Double, dy: Double) -> AffineMatrix {
        let t = degrees * .pi / 180
        let (a, b, c, d) = (s * cos(t), s * sin(t), -s * sin(t), s * cos(t))
        let cx = Double(width) / 2, cy = Double(height) / 2
        return AffineMatrix(a: a, b: b, c: c, d: d, tx: cx + dx - (a * cx + c * cy), ty: cy + dy - (b * cx + d * cy))
    }

    /// Whether two buffers have the same size and bytes.
    static func same(_ lhs: PixelBuffer, _ rhs: PixelBuffer) -> Bool {
        guard lhs.width == rhs.width, lhs.height == rhs.height else { return false }
        return lhs.components.withUnsafeBytes { p in
            rhs.components.withUnsafeBytes { q in memcmp(p.baseAddress!, q.baseAddress!, p.count) == 0 }
        }
    }

    /// The largest component difference between two same-size buffers.
    static func maxDelta(_ lhs: PixelBuffer, _ rhs: PixelBuffer) -> Float {
        lhs.components.withUnsafeBufferPointer { p in
            rhs.components.withUnsafeBufferPointer { q in
                var worst: Float = 0
                for i in 0..<min(p.count, q.count) { worst = max(worst, abs(p[i] - q[i])) }
                return worst
            }
        }
    }

    /// `backdrop` with `layer` transformed through `m` into a copy the size
    /// of `window` (a rectangle of the backdrop), then composited at the
    /// window's origin, on the CPU backend. Over a window that holds the
    /// whole transformed layer and its filter's reach, this is
    /// transform-then-composite at the backdrop's full size: the copy is
    /// transparent everywhere else, and normal over transparent changes nothing.
    func transformThenComposite(_ layer: PixelBuffer, _ m: AffineMatrix, onto backdrop: PixelBuffer,
                                window: (x: Int, y: Int, width: Int, height: Int)) throws -> PixelBuffer {
        let local = AffineMatrix(a: m.a, b: m.b, c: m.c, d: m.d, tx: m.tx - Double(window.x), ty: m.ty - Double(window.y))
        let s = try cpu.surface(layer)
        let moved = try cpu.transformed(s, local, width: window.width, height: window.height, filter: .bilinear)
        var b = try cpu.surface(backdrop)
        defer { cpu.release(s); cpu.release(moved); cpu.release(b) }
        try cpu.composite(moved, onto: &b, x: window.x, y: window.y, mode: .normal, opacity: 1)
        return try cpu.read(b)
    }

    /// `backdrop` with `layer` composited through `m`, on the CPU backend.
    func throughComposite(_ layer: PixelBuffer, _ m: AffineMatrix, onto backdrop: PixelBuffer) throws -> PixelBuffer {
        let s = try cpu.surface(layer)
        var b = try cpu.surface(backdrop)
        defer { cpu.release(s); cpu.release(b) }
        try cpu.composite(s, onto: &b, through: m, mode: .normal, opacity: 1, filter: .bilinear)
        #expect(try cpu.read(s) == layer)
        return try cpu.read(b)
    }

    /// The first and last row and column where `image` differs from `base`;
    /// nil when they are equal. Equal rows are skipped whole, and a changed
    /// row is read in from both ends only as far as its first difference.
    static func changed(_ image: PixelBuffer, from base: PixelBuffer) -> (rows: ClosedRange<Int>, cols: ClosedRange<Int>)? {
        let w = image.width, rowBytes = w * 16
        return image.components.withUnsafeBytes { v -> (rows: ClosedRange<Int>, cols: ClosedRange<Int>)? in
            base.components.withUnsafeBytes { b -> (rows: ClosedRange<Int>, cols: ClosedRange<Int>)? in
                func differs(_ offset: Int, _ count: Int) -> Bool {
                    memcmp(v.baseAddress! + offset, b.baseAddress! + offset, count) != 0
                }
                var top = Int.max, bottom = Int.min, left = Int.max, right = Int.min
                for y in 0..<image.height where differs(y * rowBytes, rowBytes) {
                    top = min(top, y)
                    bottom = y
                    var x = 0
                    while !differs(y * rowBytes + x * 16, 16) { x += 1 }
                    left = min(left, x)
                    x = w - 1
                    while !differs(y * rowBytes + x * 16, 16) { x -= 1 }
                    right = max(right, x)
                }
                return top <= bottom ? (top...bottom, left...right) : nil
            }
        }
    }

    @Test func walk() throws {
        let padded = try pad(placeAndFlip())
        try place(on: padded)
    }

    /// Steps 1 and 2, in their own scope so their 12 MP buffers are freed
    /// before the padded canvas is made: the process's resident peak stays
    /// lower for the suites that measure it alongside. Returns the composite.
    private func placeAndFlip() throws -> PixelBuffer {
        // 1. The photo through its placement onto white, then only the rotated
        // bounds' rows and columns changed, widened by bilinear's reach: at 0.5
        // the inverse steps 2 source pixels per output pixel, so radius 1
        // reaches 2 source pixels, which map back to |a|·2 + |c|·2 (about
        // 1.37, so 2) output pixels across and as many down, plus one for the
        // centre offset: 3 on every side.
        let layer = try Self.photo(width: 3000, height: 2000, block: 100, seed: 801)
        let backdrop = try PixelBuffer(width: 4000, height: 3000, fill: Self.white)
        let m = Self.placement(width: 3000, height: 2000, scale: 0.5, degrees: 30, dx: 40, dy: 25)
        let image = try throughComposite(layer, m, onto: backdrop)
        let box = try #require(m.bounds(of: 3000, 2000))
        let reach = 3
        let hit = try #require(Self.changed(image, from: backdrop))
        #expect(hit.rows.lowerBound >= box.y - reach && hit.rows.upperBound < box.y + box.height + reach, "rows \(hit.rows), box \(box)")
        #expect(hit.cols.lowerBound >= box.x - reach && hit.cols.upperBound < box.x + box.width + reach, "columns \(hit.cols), box \(box)")
        // ...and the change fills the bounds: its span is no more than a pixel inside them.
        #expect(hit.rows.lowerBound <= box.y + 1 && hit.rows.upperBound >= box.y + box.height - 2, "rows \(hit.rows), box \(box)")
        #expect(hit.cols.lowerBound <= box.x + 1 && hit.cols.upperBound >= box.x + box.width - 2, "columns \(hit.cols), box \(box)")

        // Within 1/255 of transform-then-composite, the copy made over the
        // bounds widened by 16 (well past the reach, so a pad too narrow shows)
        // rather than all 12 MP, which a debug build takes many seconds to fill.
        let margin = 16
        let window = (x: box.x - margin, y: box.y - margin, width: box.width + 2 * margin, height: box.height + 2 * margin)
        #expect(window.x >= 0 && window.y >= 0 && window.x + window.width <= 4000 && window.y + window.height <= 3000)
        let want = try transformThenComposite(layer, m, onto: backdrop, window: window)
        #expect(Self.maxDelta(image, want) <= 1 / 255)

        // 2. Flipped twice is the input (the photo layer), on either axis.
        let surface = try cpu.surface(layer)
        defer { cpu.release(surface) }
        for axis in [FlipAxis.horizontal, .vertical] {
            let once = try cpu.flipped(surface, axis)
            let twice = try cpu.flipped(once, axis)
            #expect(!Self.same(try cpu.read(once), layer), "\(axis) once")
            #expect(Self.same(try cpu.read(twice), layer), "\(axis) twice")
            cpu.release(once)
            cpu.release(twice)
        }
        return image
    }

    /// Step 3 on the composite `image`; returns the padded canvas, so the
    /// composite is freed before step 4 makes another 15 MP buffer.
    private func pad(_ image: PixelBuffer) throws -> PixelBuffer {
        // 3. Padded to 5000 x 3000 at .right: the image moves 1000 right, so
        // its right edge stays at x 5000, and the new strip is transparent.
        let padded = try image.padded(width: 5000, height: 3000, anchor: .right)
        #expect((padded.width, padded.height) == (5000, 3000))
        for y in stride(from: 0, to: 3000, by: 7) {
            #expect(try padded.pixel(x: 4999, y: y) == image.pixel(x: 3999, y: y), "right edge, row \(y)")
            #expect(try padded.pixel(x: 1000, y: y) == image.pixel(x: 0, y: y), "left edge, row \(y)")
            #expect(try padded.pixel(x: 999, y: y) == .clear, "new strip, row \(y)")
        }
        return padded
    }

    /// Step 4 on the padded canvas.
    private func place(on padded: PixelBuffer) throws {

        // 4. A 1920 x 1080 footage frame placed on the padded canvas at 0.25
        // with bilinear: only its 480 x 270 box changes, widened by
        // bilinear's reach at 0.25 (radius 1 times the inverse's step of 4
        // source pixels is 1 output pixel, plus one for the centre offset),
        // and on a white backdrop it equals transform-then-composite.
        let frame = try Self.photo(width: 1920, height: 1080, block: 60, seed: 802)
        let quarter = AffineMatrix(a: 0.25, b: 0, c: 0, d: 0.25, tx: 4400, ty: 2600)
        let frameBox = try #require(quarter.bounds(of: 1920, 1080))
        #expect((frameBox.width, frameBox.height) == (480, 270))
        let canvas = try throughComposite(frame, quarter, onto: padded)
        let frameHit = try #require(Self.changed(canvas, from: padded))
        let framePad = 2
        #expect(frameHit.rows.lowerBound >= frameBox.y - framePad
                && frameHit.rows.upperBound < frameBox.y + frameBox.height + framePad, "rows \(frameHit.rows), box \(frameBox)")
        #expect(frameHit.cols.lowerBound >= frameBox.x - framePad
                && frameHit.cols.upperBound < frameBox.x + frameBox.width + framePad, "columns \(frameHit.cols), box \(frameBox)")
        #expect(frameHit.rows.lowerBound <= frameBox.y && frameHit.rows.upperBound >= frameBox.y + frameBox.height - 1)
        #expect(frameHit.cols.lowerBound <= frameBox.x && frameHit.cols.upperBound >= frameBox.x + frameBox.width - 1)
        // The canvas's 520 x 310 window at (4380, 2580), white in the padded
        // image (the photo's box ends near x 3440, y 1850), holds the frame
        // and its reach; on the canvas it is, bit for bit, the frame
        // through-composited onto a white 520 x 310 at (20, 20), and that is
        // within 1/255 of transform-then-composite.
        let (wx, wy) = (4380, 2580)
        let local = AffineMatrix(a: 0.25, b: 0, c: 0, d: 0.25, tx: 4400 - Double(wx), ty: 2600 - Double(wy))
        let small = try PixelBuffer(width: 520, height: 310, fill: Self.white)
        #expect(Self.window(of: padded, x: wx, y: wy, is: small))
        let through = try throughComposite(frame, local, onto: small)
        #expect(Self.window(of: canvas, x: wx, y: wy, is: through))
        let whole = (x: 0, y: 0, width: 520, height: 310)
        #expect(Self.maxDelta(through, try transformThenComposite(frame, local, onto: small, window: whole)) <= 1 / 255)
    }

    /// Whether `image`'s rectangle at (`x`, `y`) the size of `part` has
    /// `part`'s bytes, compared a row at a time.
    static func window(of image: PixelBuffer, x: Int, y: Int, is part: PixelBuffer) -> Bool {
        guard x >= 0, y >= 0, x + part.width <= image.width, y + part.height <= image.height else { return false }
        let all = image.components, sub = part.components, n = part.width * 4
        return (0..<part.height).allSatisfy { row in
            let start = ((y + row) * image.width + x) * 4
            return all[start..<(start + n)].elementsEqual(sub[(row * n)..<(row * n + n)]) { $0.bitPattern == $1.bitPattern }
        }
    }
}
