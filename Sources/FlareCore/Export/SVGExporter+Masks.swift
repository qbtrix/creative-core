// SVGExporter+Masks.swift: layer masks and track mattes as W3C CSS Masking.
//
// Masks sit on the layer's <g>, in its space. A leading run of hard add masks
// is one <clipPath> when every later mask only removes; the rest paint one
// luminance <mask>, starting black when the first adds and white otherwise:
// add paints white, subtract black, intersect black outside it, inverted swaps
// the path and its outside (even-odd). Feather is the blur radius: a Gaussian
// blur of sigma feather / 3, the radius `Mask.feathered(radius:)` takes, over
// the path's box widened by three deviations. Difference throws. A track
// matte wraps the <g> in a <g mask> holding the source (ids as data-id), alpha
// or luminance; the inverted kinds paint white, then the source through its
// alpha or by difference blend. Defs share the exporter's id counter.

extension SVGExporter {
    /// The layers, frame, symbols and symbol path a run of nodes came from.
    struct Scope {
        var layers: [Layer]
        var frame: Double
        var symbols: [Symbol]
        var path: [String] = []
        var writesIDs = true // false below an instance or inside a matte
    }

    static let maskReach = 100_000.0 // half the side of every mask region

    /// Writes layer `id`'s mask and matte defs; returns its <g> attributes and matte mask id.
    static func maskDefs(for id: String, in scope: Scope, into lines: inout [String], ids: inout Int,
                         measure: (TextShape) -> [GlyphRunMetrics]) throws -> (attributes: String, matte: String?) {
        guard let layer = scope.layers.first(where: { $0.id == id }) else { return ("", nil) }
        var attributes = ""
        let masks = layer.masks
        if masks.contains(where: { $0.mode == .difference }) { throw SVGExportError.unsupported("mask difference") }
        let hard = masks.prefix { $0.mode == .add && $0.feather == 0 && $0.opacity == 1 && !$0.inverted }
        let clips = !hard.isEmpty && masks.dropFirst(hard.count).allSatisfy { $0.mode != .add }
        if clips {
            let clip = nextID("c", &ids)
            lines.append("<clipPath id=\"\(clip)\">")
            for mask in hard { lines.append("<path d=\"\(try pathData(mask.path))\"/>") }
            lines.append("</clipPath>")
            attributes += " clip-path=\"url(#\(clip))\""
        }
        let painted = clips ? Array(masks.dropFirst(hard.count)) : masks
        if let first = painted.first {
            var body = first.mode == .add && !clips ? [] : [try fullRect()]
            for mask in painted { body.append(try paint(mask, into: &lines, ids: &ids)) }
            let id = try openMask(type: nil, into: &lines, ids: &ids)
            lines += body + ["</mask>"]
            attributes += " mask=\"url(#\(id))\""
        }
        guard let matte = layer.matte else { return (attributes, nil) }
        return (attributes, try matteMask(matte, in: scope, into: &lines, ids: &ids, measure: measure))
    }

    /// The source layer drawn into a mask by the matte's kind; returns its id.
    static func matteMask(_ matte: TrackMatte, in scope: Scope, into lines: inout [String], ids: inout Int,
                          measure: (TextShape) -> [GlyphRunMetrics]) throws -> String {
        guard var source = scope.layers.first(where: { $0.id == matte.sourceLayerID }) else {
            throw SVGExportError.unsupported("matte source")
        }
        if source.matte != nil { throw SVGExportError.unsupported("nested matte") }
        source.isVisible = true
        let list = RenderList(layers: [source], owner: .scene(""), frame: scope.frame, symbols: scope.symbols, path: scope.path)
        if list.isTruncated { throw SVGExportError.sceneTooLarge }
        let inner = Scope(layers: [source], frame: scope.frame, symbols: scope.symbols, path: scope.path, writesIDs: false)
        var body: [String] = []
        for node in sampled(list.nodes, layers: [source], frame: scope.frame, symbols: scope.symbols) {
            try emit(node, in: inner, into: &body, gradients: &ids, measure: measure)
        }
        var wrapper: String?
        if matte.kind == .alphaInverted {
            let filter = nextID("f", &ids)
            lines += ["<filter id=\"\(filter)\">",
                      "<feColorMatrix type=\"matrix\" values=\"0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0\"/>", "</filter>"]
            wrapper = "<g filter=\"url(#\(filter))\">"
        } else if matte.kind == .lumaInverted {
            wrapper = "<g style=\"mix-blend-mode:difference\">"
        }
        let id = try openMask(type: matte.kind == .alpha ? "alpha" : "luminance", into: &lines, ids: &ids)
        if let wrapper { lines += [try fullRect(), wrapper] + body + ["</g>"] } else { lines += body }
        lines.append("</mask>")
        return id
    }

    /// One painted mask as a <path>, its blur filter written to `lines` first.
    static func paint(_ mask: LayerMask, into lines: inout [String], ids: inout Int) throws -> String {
        let outside = (mask.mode == .intersect) != mask.inverted
        var d = try pathData(mask.path)
        let r = try number(maskReach)
        if outside { d = "M-\(r) -\(r) L\(r) -\(r) L\(r) \(r) L-\(r) \(r) Z " + d }
        var out = "<path d=\"\(d)\" fill=\"\(mask.mode == .add ? "#fff" : "#000")\""
        if mask.opacity != 1 { out += " fill-opacity=\"\(try number(mask.opacity))\"" }
        if outside { out += " fill-rule=\"evenodd\"" }
        if mask.feather != 0 {
            let sigma = mask.feather / 3
            let filter = nextID("f", &ids)
            var region = try regionAttributes()
            if !outside, let b = mask.path.bounds {
                let k = 3 * sigma
                region = try box(b.minX - k, b.minY - k, b.maxX - b.minX + 2 * k, b.maxY - b.minY + 2 * k)
            }
            lines += ["<filter id=\"\(filter)\" filterUnits=\"userSpaceOnUse\"\(region)>",
                      "<feGaussianBlur stdDeviation=\"\(try number(sigma))\"/>", "</filter>"]
            out += " filter=\"url(#\(filter))\""
        }
        return out + "/>"
    }

    /// Appends a <mask> open tag over the mask region; returns its id.
    static func openMask(type: String?, into lines: inout [String], ids: inout Int) throws -> String {
        let id = nextID("m", &ids)
        let kind = type.map { " mask-type=\"\($0)\"" } ?? ""
        lines.append("<mask id=\"\(id)\"\(kind) maskUnits=\"userSpaceOnUse\"\(try regionAttributes())>")
        return id
    }

    static func regionAttributes() throws -> String { try box(-maskReach, -maskReach, 2 * maskReach, 2 * maskReach) }

    static func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) throws -> String {
        " x=\"\(try number(x))\" y=\"\(try number(y))\" width=\"\(try number(w))\" height=\"\(try number(h))\""
    }
    static func nextID(_ prefix: String, _ ids: inout Int) -> String { defer { ids += 1 }; return "\(prefix)\(ids)" }
    static func fullRect() throws -> String { "<rect\(try regionAttributes()) fill=\"#fff\"/>" }
}
