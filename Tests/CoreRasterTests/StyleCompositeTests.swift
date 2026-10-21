// StyleCompositeTests.swift: the layer style stack (layer-style-engine LE-1,
// LE-4): the contract types' defaults and StrokePosition's coding, and
// `styled(_:)` and `reach`: identity, fill opacity, modes, the fixed paint
// order, clipping, spread, reach, equality with the single effects, error
// wording, and a seeded fuzz of bad parameters.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreRaster
import Testing

@Suite struct StyleCompositeTests {
    @Test func entryAndStackDefaults() {
        let entry = StyleEntry(op: .overlay(.color(StyleFixtures.white)))
        #expect(entry.mode == .normal && entry.opacity == 1 && entry.isEnabled)
        let stack = LayerStyleStack(entries: [entry])
        #expect(stack.fillOpacity == 1 && stack.entries == [entry])
        #expect(StyleFixtures.everyOp().entries.count == 7)
    }

    @Test func strokePositionCodesAsItsName() throws {
        let data = try JSONEncoder().encode([StrokePosition.outside])
        #expect(String(decoding: data, as: UTF8.self) == "[\"outside\"]")
        #expect(try JSONDecoder().decode([StrokePosition].self, from: Data("[\"center\"]".utf8)) == [.center])
        #expect(StrokePosition.allCases.count == 3)
    }

    @Test func disabledOrZeroOpacityEntriesAreIdentity() throws {
        let badge = try StyleFixtures.badge()
        var (off, zero) = (StyleFixtures.everyOp(), StyleFixtures.everyOp())
        for i in off.entries.indices { (off.entries[i].isEnabled, zero.entries[i].opacity) = (false, 0) }
        #expect(try badge.styled(off) == badge && badge.styled(zero) == badge)
    }

    @Test func fillOpacityFadesOnlyTheLayer() throws {
        let badge = try StyleFixtures.badge()
        let glow = StyleEntry(op: .outerGlow(color: StyleFixtures.white, spread: 0, size: 4))
        let full = try badge.styled(LayerStyleStack(entries: [glow]))
        let faded = try badge.styled(LayerStyleStack(entries: [glow], fillOpacity: 0))
        #expect(try full.pixel(x: 4, y: 16) == faded.pixel(x: 4, y: 16))
        #expect(try faded.pixel(x: 24, y: 16).a < full.pixel(x: 24, y: 16).a)
    }

    /// A Multiply grey overlay on a Normal grey one gives grey times grey, so the clipped entry's mode is applied.
    @Test func multiplyOverlayMultipliesTheOneBelow() throws {
        let badge = try StyleFixtures.badge()
        let grey = StyleEntry(op: .overlay(.color(RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1))))
        var times = grey
        times.mode = .multiply
        let normal = try badge.styled(LayerStyleStack(entries: [grey, grey])).pixel(x: 24, y: 16)
        let multiply = try badge.styled(LayerStyleStack(entries: [grey, times])).pixel(x: 24, y: 16)
        #expect(abs(multiply.r - 0.25) < 1e-5 && multiply.r < normal.r)
    }

    /// Under-layer modes apply among the under-layers: a Screen glow over a Normal drop shadow is not a Normal glow.
    @Test func screenGlowOverShadowDiffersFromNormal() throws {
        let badge = try StyleFixtures.badge()
        let shadow = StyleEntry(op: .dropShadow(color: RGBA(r: 0.6, g: 0.2, b: 0.2, a: 1), dx: 0, dy: 0, spread: 0, blur: 6))
        let glow = StyleEntry(op: .outerGlow(color: RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1), spread: 0, size: 4))
        var screen = glow
        screen.mode = .screen
        let normal = try badge.styled(LayerStyleStack(entries: [shadow, glow]))
        let screened = try badge.styled(LayerStyleStack(entries: [shadow, screen]))
        #expect(try screened.pixel(x: 6, y: 16).r > normal.pixel(x: 6, y: 16).r)
    }

    /// The layer is added onto the knocked-out under-layers, so a lone drop
    /// shadow or outside stroke equals the single effect exactly.
    @Test func loneShadowAndOutsideStrokeEqualTheEffect() throws {
        let badge = try StyleFixtures.badge(), black = StyleFixtures.black
        for blur in [0.0, 4] {
            let shadow = StyleEntry(op: .dropShadow(color: black, dx: 3, dy: 2, spread: 0, blur: blur))
            #expect(try badge.styled(LayerStyleStack(entries: [shadow])) == badge.shadowed(color: black, dx: 3, dy: 2, blur: blur, inner: false))
        }
        let stroke = StyleEntry(op: .stroke(fill: .color(black), width: 2, position: .outside))
        #expect(try badge.styled(LayerStyleStack(entries: [stroke])) == badge.stroked(color: black, width: 2, position: .outside))
    }

    /// Stroke width 0 at every position, bevel size 0 in every shape and a
    /// clear overlay draw nothing (a 0 px shadow or glow is a hard edge effect, not identity).
    @Test func zeroWidthStrokeZeroBevelAndClearOverlayAreIdentity() throws {
        let badge = try StyleFixtures.badge()
        var ops: [StyleOp] = StrokePosition.allCases.map { .stroke(fill: .color(StyleFixtures.black), width: 0, position: $0) }
        ops += BevelShape.allCases.map { .bevel(StyleFixtures.bevel(shape: $0, size: 0)) }
        ops.append(.overlay(.color(RGBA(r: 0, g: 0, b: 0, a: 0))))
        for op in ops {
            #expect(try badge.styled(LayerStyleStack(entries: [StyleEntry(op: op)])) == badge, "\(op)")
        }
    }

    @Test func shadowBlurErrorNamesBlur() throws {
        let badge = try StyleFixtures.badge()
        let shadow = StyleEntry(op: .dropShadow(color: StyleFixtures.black, dx: 0, dy: 0, spread: 0, blur: 2_000))
        #expect(throws: RasterError.invalid("drop shadow blur 2000.0: must be finite and in 0...1000")) {
            try badge.styled(LayerStyleStack(entries: [shadow]))
        }
    }

    @Test func entryOpacityErrorNamesEntry() throws {
        let badge = try StyleFixtures.badge()
        let entries = [StyleEntry(op: .overlay(.color(StyleFixtures.black))),
                       StyleEntry(op: .outerGlow(color: StyleFixtures.white, spread: 0, size: 2), opacity: 2)]
        #expect(throws: RasterError.invalid("style entry 1 (outer glow) opacity 2.0: must be a finite value in 0...1")) {
            try badge.styled(LayerStyleStack(entries: entries))
        }
    }

    @Test func paintOrderIsFixed() throws {
        let badge = try StyleFixtures.badge()
        let stroke = StyleEntry(op: .stroke(fill: .color(StyleFixtures.black), width: 2, position: .inside))
        let overlay = StyleEntry(op: .overlay(.color(RGBA(r: 1, g: 0, b: 0, a: 1))))
        let a = try badge.styled(LayerStyleStack(entries: [stroke, overlay]))
        let b = try badge.styled(LayerStyleStack(entries: [overlay, stroke]))
        #expect(a == b)
        #expect(try a.pixel(x: 9, y: 16).r < 0.1)
    }

    @Test func overlayStaysInside() throws {
        let badge = try StyleFixtures.badge()
        let out = try badge.styled(LayerStyleStack(entries: [StyleEntry(op: .overlay(.color(StyleFixtures.black)))]))
        #expect(try EffectFixtures.alphaSum(out) == EffectFixtures.alphaSum(badge))
    }

    @Test func fullSpreadGivesAHardEdge() throws {
        let badge = try StyleFixtures.badge()
        let shadow = StyleEntry(op: .dropShadow(color: StyleFixtures.black, dx: 0, dy: 0, spread: 1, blur: 4))
        let out = try badge.styled(LayerStyleStack(entries: [shadow], fillOpacity: 0))
        #expect(try out.pixel(x: 5, y: 16).a > 0.99)
    }

    @Test func reachCoversTheDropShadow() {
        let shadow = StyleEntry(op: .dropShadow(color: StyleFixtures.black, dx: 6, dy: 6, spread: 0, blur: 12))
        #expect(LayerStyleStack(entries: [shadow]).reach == 21)
    }

    @Test func nonFiniteValuesThrow() throws {
        let badge = try StyleFixtures.badge()
        var rng = SplitMix64(seed: 0x57_11E)
        let bad = [Double.nan, .infinity, -.infinity]
        for _ in 0..<32 {
            let v = bad[Int(rng.next() % 3)]
            let op: StyleOp = rng.next() % 2 == 0
                ? .dropShadow(color: StyleFixtures.black, dx: v, dy: 0, spread: 0, blur: 2)
                : .outerGlow(color: StyleFixtures.white, spread: 0, size: v)
            #expect(throws: RasterError.self) { try badge.styled(LayerStyleStack(entries: [StyleEntry(op: op)])) }
        }
    }

    /// 200 seeded stacks of one to three entries, with colour and gradient
    /// fills, seeded on/off switches and entry opacities: a stack throws
    /// exactly when an entry opacity or the fill opacity is bad, or an active
    /// entry (enabled, opacity above 0) has a value NaN, infinite or past its
    /// cap, and otherwise draws a finite buffer of the same size.
    @Test func fuzz() throws {
        let badge = try StyleFixtures.badge(width: 24, height: 20, pad: 5)
        var rng = SplitMix64(seed: 0x5_7F1E)
        let good = [0.0, 1, 2.5, 4], wild = [Double.nan, .infinity, -.infinity, 2_000]
        for _ in 0..<200 {
            var bad = false
            // Offsets and colours have no cap, so only their non-finite values are bad.
            func value(_ pool: [Double] = good, capped: Bool = true) -> Double {
                guard rng.next() % 8 == 0 else { return pool[Int(rng.next() % UInt64(pool.count))] }
                bad = true
                return wild[Int(rng.next() % UInt64(capped ? 4 : 3))]
            }
            func spread() -> Double { value([0, 0.5, 1]) }
            var entries: [StyleEntry] = []
            for _ in 0..<(1 + Int(rng.next() % 3)) {
                let wasBad = bad
                bad = false
                let tint = RGBA(r: 0.2, g: 0.4, b: Float(value([0, 0.5, 1], capped: false)), a: 1)
                let op: StyleOp
                switch rng.next() % 8 {
                case 0: op = .dropShadow(color: tint, dx: value(capped: false), dy: value(capped: false), spread: spread(), blur: value())
                case 1: op = .innerShadow(color: tint, dx: value(capped: false), dy: value(capped: false), spread: spread(), blur: value())
                case 2: op = .outerGlow(color: tint, spread: spread(), size: value())
                case 3: op = .innerGlow(color: tint, spread: spread(), size: value())
                case 4: op = .stroke(fill: .color(tint), width: value(), position: StrokePosition.allCases[Int(rng.next() % 3)])
                case 5: op = .overlay(.color(tint))
                case 6:
                    let count = 2 + Int(rng.next() % 3)
                    let stops = (0..<count).map { RasterGradientStop(offset: Float($0) / Float(count - 1), color: $0 == 0 ? tint : StyleFixtures.white) }
                    let from = Mask.Point(x: value(capped: false), y: value(capped: false))
                    let to = Mask.Point(x: from.x + 3 + value(capped: false), y: from.y - 2)
                    let shape = [RasterGradientShape.linear, .radial, .angle, .reflected, .diamond][Int(rng.next() % 5)]
                    let fill = StyleFill.gradient(stops: stops, shape: shape, from: from, to: to)
                    op = rng.next() % 2 == 0 ? .overlay(fill) : .stroke(fill: fill, width: value(), position: StrokePosition.allCases[Int(rng.next() % 3)])
                default:
                    var bevel = StyleFixtures.bevel(size: value())
                    bevel.highlight = tint
                    op = .bevel(bevel)
                }
                // A bad value in an inactive entry is never read; a bad opacity always throws.
                let isEnabled = rng.next() % 4 != 0
                let opacity = [Float(0), 0.5, 1, 1, .nan, .infinity, 2][Int(rng.next() % 7)]
                bad = wasBad || (bad && isEnabled && opacity > 0) || !(0...1).contains(opacity)
                entries.append(StyleEntry(op: op, mode: rng.next() % 2 == 0 ? .normal : .multiply, opacity: opacity, isEnabled: isEnabled))
            }
            let stack = LayerStyleStack(entries: entries, fillOpacity: Float(value([0, 0.5, 1])))
            if bad {
                #expect(throws: RasterError.self) { try badge.styled(stack) }
            } else {
                let out = try badge.styled(stack)
                #expect(out.width == badge.width && out.height == badge.height)
                #expect(try (0..<out.height).allSatisfy { y in try (0..<out.width).allSatisfy { try out.pixel(x: $0, y: y).isFinite } })
            }
        }
    }
}
