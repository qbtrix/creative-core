// StyleCompositeTests.swift: the layer style stack (layer-style-engine LE-1,
// LE-4): the contract types' defaults and StrokePosition's coding, and
// `styled(_:)` and `reach`: identity, fill opacity, modes, the fixed paint
// order, clipping, spread, reach, and a seeded fuzz of bad parameters.
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

    @Test func multiplyOverlayIsDarkerThanNormal() throws {
        let badge = try StyleFixtures.badge()
        let grey = RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1)
        let normal = try badge.styled(LayerStyleStack(entries: [StyleEntry(op: .overlay(.color(grey)))]))
        let multiply = try badge.styled(LayerStyleStack(entries: [StyleEntry(op: .overlay(.color(grey)), mode: .multiply)]))
        #expect(try multiply.pixel(x: 24, y: 16).r <= normal.pixel(x: 24, y: 16).r)
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

    /// 200 seeded stacks of one to three entries: a stack throws exactly when
    /// one of its values is NaN, infinite or past its cap, and otherwise draws
    /// a finite buffer of the same size.
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
                let tint = RGBA(r: 0.2, g: 0.4, b: Float(value([0, 0.5, 1], capped: false)), a: 1)
                let op: StyleOp
                switch rng.next() % 7 {
                case 0: op = .dropShadow(color: tint, dx: value(capped: false), dy: value(capped: false), spread: spread(), blur: value())
                case 1: op = .innerShadow(color: tint, dx: value(capped: false), dy: value(capped: false), spread: spread(), blur: value())
                case 2: op = .outerGlow(color: tint, spread: spread(), size: value())
                case 3: op = .innerGlow(color: tint, spread: spread(), size: value())
                case 4: op = .stroke(fill: .color(tint), width: value(), position: StrokePosition.allCases[Int(rng.next() % 3)])
                case 5: op = .overlay(.color(tint))
                default:
                    var bevel = StyleFixtures.bevel(size: value())
                    bevel.highlight = tint
                    op = .bevel(bevel)
                }
                entries.append(StyleEntry(op: op, mode: rng.next() % 2 == 0 ? .normal : .multiply))
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
