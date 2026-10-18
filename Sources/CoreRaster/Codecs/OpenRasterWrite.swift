// OpenRasterWrite.swift: saves a `LayeredImage` as an OpenRaster file, from
// the published OpenRaster spec, so that `OpenRaster.read` reopens it equal.
// Entries: `mimetype` first (ZipStore's container rules), `stack.xml`, one
// PNG per pixel layer at `data/<n>.png` through the injected `PixelCodec`,
// `mergedimage.png` from `composite`, `Thumbnails/thumbnail.png` (the
// composite scaled so its longest side is 256, never up), and the app's
// `extra` entries.
// Invariants a writer must keep:
// - Nothing is encoded until the whole image is validated: bits per channel
//   8 (16 is `unsupported` until colour-profiles), no embedded profile (ORA
//   carries none), a composite the canvas size (the spec requires
//   `mergedimage.png`), no mask or clipping (ORA has neither), every opacity
//   finite in 0...1, the canvas and every layer within `OpenRaster.maxSide`
//   and `PixelBuffer.maxPixels`, offsets within `StackXML.maxOffset`, at most
//   `OpenRaster.maxLayers` layers and groups, nesting the reader accepts
//   (`OpenRaster.maxDepth` stacks, the root first, a layer one below), no NUL in a name, and no `extra` path that
//   collides with a standard entry. Each failure throws a `CodecError`.
// - `stack.xml` lists children top first, the reverse of `nodes`. Layers
//   carry their canvas offsets and stacks none, names are UTF-8 with the
//   five entities and control characters escaped, and opacity is written as
//   the Float's shortest round-trip text, so it reads back exactly. A nil
//   group blend (pass through) writes no `composite-op`. A group's `isOpen`
//   is not kept: ORA has no such attribute, so groups reopen open.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension OpenRaster {
    static let thumbnailSide = 256
    static let standardPaths: Set<String> = ["mimetype", "stack.xml", "mergedimage.png", "Thumbnails/thumbnail.png"]

    /// The bytes `write` returns: validates first, then encodes.
    static func encode(_ image: LayeredImage, pixels: any PixelCodec, extra: [String: Data]) throws -> Data {
        switch image.bitsPerChannel {
        case 8: break
        case 16: throw CodecError.unsupported("16-bit channels")
        case let bits: throw CodecError.unsupported("\(bits) bits per channel")
        }
        guard image.profile == nil else { throw CodecError.unsupported("an embedded colour profile") }
        try checkSize(image.width, image.height, "canvas")
        guard let composite = image.composite else { throw CodecError.unsupported("an image without a composite") }
        guard composite.width == image.width, composite.height == image.height else {
            throw CodecError.unsupported("a \(composite.width)x\(composite.height) composite on a \(image.width)x\(image.height) canvas")
        }
        var stack = StackWriter()
        try stack.add(image.nodes, depth: 0)
        let layerPaths = stack.layers.indices.map { "data/\($0).png" }
        let reserved = standardPaths.union(layerPaths)
        if let path = extra.keys.sorted().first(where: reserved.contains) {
            throw CodecError.unsupported("extra entry \(path) collides with a standard entry")
        }

        let longest = max(image.width, image.height), side = min(longest, thumbnailSide)
        let thumbnail: PixelBuffer
        do {
            thumbnail = longest == side ? composite
                : try composite.resized(width: max(1, (image.width * side + longest / 2) / longest),
                                        height: max(1, (image.height * side + longest / 2) / longest), filter: .bilinear)
        } catch { throw CodecError.unsupported("the thumbnail: \(error)") }
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<image version=\"0.0.5\" w=\"\(image.width)\" h=\"\(image.height)\">"
            + "<stack>\(stack.xml)</stack></image>\n"
        var files = extra
        files["mimetype"] = Data("image/openraster".utf8)
        files["stack.xml"] = Data(xml.utf8)
        for (path, buffer) in zip(layerPaths, stack.layers) + [("mergedimage.png", composite), ("Thumbnails/thumbnail.png", thumbnail)] {
            files[path] = try codec(path) { try pixels.encodePNG(buffer, bitsPerChannel: 8) }
        }
        return try ZipStore.archive(files, first: "mimetype")
    }
}

/// Builds `stack.xml`'s children of the root stack and collects the layer pixels in `src` order.
private struct StackWriter {
    var xml = "", layers: [PixelBuffer] = [], count = 0

    /// `nodes` (bottom to top) as elements top first, under `depth` groups.
    mutating func add(_ nodes: [LayerNode], depth: Int) throws {
        for node in nodes.reversed() {
            // The reader pushes each element under `image`, the root stack and `depth` groups,
            // and opens a stack at most `maxDepth` deep and a layer one level below.
            let room = if case .group = node { 0 } else { 1 }
            guard depth + 2 <= OpenRaster.maxDepth + room else { throw CodecError.tooLarge("an element under \(depth) groups") }
            count += 1
            guard count <= OpenRaster.maxLayers else { throw CodecError.tooLarge("more than \(OpenRaster.maxLayers) layers and groups") }
            switch node {
            case .pixels(let layer):
                guard layer.mask == nil, !layer.clipsToBelow else { throw CodecError.unsupported("a mask or clipping on \"\(layer.name)\"") }
                try OpenRaster.checkSize(layer.pixels.width, layer.pixels.height, "layer \"\(layer.name)\"")
                guard layer.x.magnitude <= UInt(StackXML.maxOffset), layer.y.magnitude <= UInt(StackXML.maxOffset) else {
                    throw CodecError.tooLarge("layer \"\(layer.name)\" offset \(layer.x), \(layer.y)")
                }
                xml += "<layer \(try Self.common(layer.name, layer.opacity, layer.isHidden, layer.blendMode)) src=\"data/\(layers.count).png\""
                    + " x=\"\(layer.x)\" y=\"\(layer.y)\"/>"
                layers.append(layer.pixels)
            case .group(let group):
                xml += "<stack \(try Self.common(group.name, group.opacity, group.isHidden, group.blendMode))>"
                try add(group.children, depth: depth + 1)
                xml += "</stack>"
            }
        }
    }

    /// The name, opacity, visibility and composite-op attributes.
    static func common(_ name: String, _ opacity: Float, _ isHidden: Bool, _ mode: BlendMode?) throws -> String {
        guard (0...1).contains(opacity) else { throw CodecError.unsupported("opacity \(opacity) of \"\(name)\": must be finite in 0...1") }
        var text = "name=\"\(try escaped(name))\" opacity=\"\(opacity)\" visibility=\"\(isHidden ? "hidden" : "visible")\""
        if let mode {
            guard let op = opKeys[mode] else { throw CodecError.unsupported("blend mode \(mode)") }
            text += " composite-op=\"\(op)\""
        }
        return text
    }

    /// The reader's composite-op table, inverted.
    static let opKeys: [BlendMode: String] = Dictionary(StackXML.blendModes.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

    /// `text` as an attribute value: the five entities and control characters as references.
    static func escaped(_ text: String) throws -> String {
        let named: [Unicode.Scalar: String] = ["&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&apos;"]
        var out = ""
        for scalar in text.unicodeScalars {
            if let entity = named[scalar] {
                out += entity
            } else if scalar.value < 0x20 {
                guard scalar.value != 0 else { throw CodecError.unsupported("a NUL character in the name \"\(text)\"") }
                out += "&#\(scalar.value);"
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
