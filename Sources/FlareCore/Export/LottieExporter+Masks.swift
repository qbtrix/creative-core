// LottieExporter+Masks.swift: layer masks and track mattes (lottie-spec Mask, tt, td).
//
// Masks are `masksProperties` (mode a, s, i, f; inv; o times 100; one path,
// written closed since an open mask subpath is implicitly closed; x, the spec's expansion, 0) with `hasMask`. Lottie masks have no
// feather, so a feathered mask throws. A matted layer gets `tt` 1...4 and its
// source sits directly above with `td: 1`: a hidden source already there and
// used once is marked in place (unhidden), else a copy numbered after the
// scene's layers is written. Nested mattes and symbol layers with masks throw.

extension LottieExporter {
    /// The scene's layers, top first, with their masks and mattes.
    static func layers(of scene: Scene, symbols: [Symbol]) throws -> [LottieLayer] {
        let all = scene.layers
        var users: [String: Int] = [:]
        for matte in all.compactMap(\.matte) { users[matte.sourceLayerID, default: 0] += 1 }
        var out: [LottieLayer] = []
        var next = all.count + 1
        func written(_ layer: Layer, index: Int) throws -> LottieLayer {
            var item = try LottieLayer(layer, index: index, durationFrames: scene.durationFrames, symbols: symbols)
            if !layer.masks.isEmpty { (item.hasMask, item.masksProperties) = (true, try layer.masks.map(LottieMask.init)) }
            return item
        }
        for (index, layer) in all.enumerated().reversed() {
            var item = try written(layer, index: index + 1)
            guard let matte = layer.matte else { out.append(item); continue }
            guard let s = all.firstIndex(where: { $0.id == matte.sourceLayerID }) else {
                throw LottieExportError.unsupported("matte source")
            }
            if all[s].matte != nil { throw LottieExportError.unsupported("nested matte") }
            item.tt = [.alpha: 1, .alphaInverted: 2, .luma: 3, .lumaInverted: 4][matte.kind]
            if s == index + 1, !all[s].isVisible, users[all[s].id] == 1, !out.isEmpty {
                (out[out.count - 1].td, out[out.count - 1].hd) = (1, false)
                out.append(item)
            } else {
                var copy = try written(all[s], index: next)
                next += 1
                (copy.td, copy.hd) = (1, false)
                out += [copy, item]
            }
        }
        return out
    }
}

struct LottieMask: Encodable, Sendable {
    var inv: Bool
    var mode: String
    var o: LottieStatic<Double>
    var pt: LottieStatic<LottieBezier>
    var x = LottieStatic(0.0)

    init(_ mask: LayerMask) throws {
        let opacity = try LottieExporter.finite(mask.opacity)
        guard try LottieExporter.finite(mask.feather) == 0 else { throw LottieExportError.unsupported("mask feather") }
        let paths = try LottieExporter.beziers(mask.path)
        guard paths.count == 1, var path = paths.first else { throw LottieExportError.unsupported("mask path") }
        path.c = true // an open mask subpath is implicitly closed
        inv = mask.inverted
        mode = [.add: "a", .subtract: "s", .intersect: "i", .difference: "f"][mask.mode] ?? "a"
        o = LottieStatic(min(max(opacity, 0), 1) * 100)
        pt = LottieStatic(path)
    }
}
