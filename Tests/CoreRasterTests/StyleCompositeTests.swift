// StyleCompositeTests.swift: the layer style stack (layer-style-engine LE-1,
// LE-4). The contract types' defaults and StrokePosition's coding run now; the
// compositing checks wait on LE-4, which builds `styled(_:)` and `reach`.
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

    @Test(.disabled("waits on LE-4")) func disabledOrZeroOpacityEntriesAreIdentity() throws {
        let badge = try StyleFixtures.badge()
        var (off, zero) = (StyleFixtures.everyOp(), StyleFixtures.everyOp())
        for i in off.entries.indices { (off.entries[i].isEnabled, zero.entries[i].opacity) = (false, 0) }
        #expect(try badge.styled(off) == badge && badge.styled(zero) == badge)
    }

    @Test(.disabled("waits on LE-4")) func fillOpacityFadesOnlyTheLayer() throws {
        let badge = try StyleFixtures.badge()
        let glow = StyleEntry(op: .outerGlow(color: StyleFixtures.white, spread: 0, size: 4))
        let full = try badge.styled(LayerStyleStack(entries: [glow]))
        let faded = try badge.styled(LayerStyleStack(entries: [glow], fillOpacity: 0))
        #expect(try full.pixel(x: 4, y: 16) == faded.pixel(x: 4, y: 16))
        #expect(try faded.pixel(x: 24, y: 16).a < full.pixel(x: 24, y: 16).a)
    }

    @Test(.disabled("waits on LE-4")) func multiplyOverlayIsDarkerThanNormal() throws {
        let badge = try StyleFixtures.badge()
        let grey = RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1)
        let normal = try badge.styled(LayerStyleStack(entries: [StyleEntry(op: .overlay(.color(grey)))]))
        let multiply = try badge.styled(LayerStyleStack(entries: [StyleEntry(op: .overlay(.color(grey)), mode: .multiply)]))
        #expect(try multiply.pixel(x: 24, y: 16).r <= normal.pixel(x: 24, y: 16).r)
    }

    @Test(.disabled("waits on LE-4")) func paintOrderIsFixed() throws {
        let badge = try StyleFixtures.badge()
        let stroke = StyleEntry(op: .stroke(fill: .color(StyleFixtures.black), width: 2, position: .inside))
        let overlay = StyleEntry(op: .overlay(.color(RGBA(r: 1, g: 0, b: 0, a: 1))))
        let a = try badge.styled(LayerStyleStack(entries: [stroke, overlay]))
        let b = try badge.styled(LayerStyleStack(entries: [overlay, stroke]))
        #expect(a == b)
        #expect(try a.pixel(x: 9, y: 16).r < 0.1)
    }

    @Test(.disabled("waits on LE-4")) func overlayStaysInside() throws {
        let badge = try StyleFixtures.badge()
        let out = try badge.styled(LayerStyleStack(entries: [StyleEntry(op: .overlay(.color(StyleFixtures.black)))]))
        #expect(try EffectFixtures.alphaSum(out) == EffectFixtures.alphaSum(badge))
    }

    @Test(.disabled("waits on LE-4")) func fullSpreadGivesAHardEdge() throws {
        let badge = try StyleFixtures.badge()
        let shadow = StyleEntry(op: .dropShadow(color: StyleFixtures.black, dx: 0, dy: 0, spread: 1, blur: 4))
        let out = try badge.styled(LayerStyleStack(entries: [shadow], fillOpacity: 0))
        #expect(try out.pixel(x: 5, y: 16).a > 0.99)
    }

    @Test(.disabled("waits on LE-4")) func reachCoversTheDropShadow() {
        let shadow = StyleEntry(op: .dropShadow(color: StyleFixtures.black, dx: 6, dy: 6, spread: 0, blur: 12))
        #expect(LayerStyleStack(entries: [shadow]).reach == 21)
    }

    @Test(.disabled("waits on LE-4")) func nonFiniteValuesThrow() throws {
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
}
