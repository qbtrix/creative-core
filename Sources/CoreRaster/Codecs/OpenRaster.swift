// OpenRaster.swift: the OpenRaster (.ora) codec's entry points, from the
// published OpenRaster spec: a stored-entry zip with `mimetype`, `stack.xml`
// and one PNG per layer through the injected `PixelCodec`. Reading checks the
// `mimetype`, parses `stack.xml` with StackXML, turns its top-first stacks into
// bottom-to-top nodes (nested stacks become groups, stack offsets add to their
// layers'), sums every `src` and `mergedimage.png` IHDR within
// `maxTotalPixels`, then decodes each once. ORA carries no ICC
// profile, so `profile` is nil. `write`'s validation and encoding live in
// OpenRasterWrite.swift.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Reads and writes OpenRaster files as a `LayeredImage`.
public enum OpenRaster {
    /// The longest canvas or layer side read, as for PSD.
    public static let maxSide = PSD.maxSide
    /// The most layers and nested stacks (the root stack not counted) one
    /// `stack.xml` may hold, as for PSD.
    public static let maxLayers = PSD.maxLayers
    /// The most nested `<stack>` levels `stack.xml` may have, the root stack
    /// counted as the first: `maxDepth` levels read, one more throws.
    public static let maxDepth = 256
    /// The most pixels every layer PNG and `mergedimage.png` may hold
    /// together, summed from their IHDRs before any is decoded, as for PSD.
    public static let maxTotalPixels = PSD.maxTotalPixels

    /// Opens `.ora` bytes, decoding each layer's PNG with `pixels`.
    /// Throws `notThisFormat` without the OpenRaster `mimetype`, `damaged`
    /// for a missing `stack.xml`, a missing or repeated layer source (naming
    /// it), a source or `mergedimage.png` that does not start with a PNG
    /// signature and IHDR, or a `mergedimage.png` other than the canvas size,
    /// `tooLarge` for an image over `maxSide` or `PixelBuffer.maxPixels`
    /// (read from its IHDR before decoding, and checked again after) or for
    /// IHDR sizes summing over `maxTotalPixels`, and whatever `ZipStore`,
    /// `StackXML` and `pixels` throw. Every image is sized and summed before
    /// any is decoded, and each is decoded once.
    public static func read(_ data: Data, pixels: any PixelCodec) throws -> LayeredImage {
        let entries = try ZipStore.entries(data)
        guard entries["mimetype"] == Data("image/openraster".utf8) else { throw CodecError.notThisFormat }
        guard let xml = entries["stack.xml"] else { throw CodecError.damaged("no stack.xml") }
        let stack = try StackXML.parse(xml)
        // Every source in the tree, then the merged image: sized and summed before any decode.
        var sources: [String] = [], used: Set<String> = []
        // Both tree walks keep an explicit stack: recursing maxDepth deep overflows the 512 KB stack
        // of a secondary thread on macOS. This one is depth first in file order (top first).
        var pending = [stack.nodes[...]]
        while let top = pending.indices.last {
            switch pending[top].popFirst() {
            case .layer(let layer)?:
                guard let src = layer.src else { throw CodecError.damaged("layer \(layer.name) has no src") }
                guard used.insert(src).inserted else { throw CodecError.damaged("layer source \(src) repeats") }
                sources.append(src)
            case .stack(_, let children)?: pending.append(children[...])
            case nil: pending.removeLast()
            }
        }
        let merged = "mergedimage.png"
        if entries[merged] != nil, !used.contains(merged) { sources.append(merged) }
        var total = 0
        for path in sources {
            guard let bytes = entries[path] else { throw CodecError.damaged("missing layer source \(path)") }
            let sum = total.addingReportingOverflow(try pngPixels(bytes, path))
            guard !sum.overflow, sum.partialValue <= maxTotalPixels else {
                throw CodecError.tooLarge("images over \(maxTotalPixels) pixels in all at \(path)")
            }
            total = sum.partialValue
        }
        var decoded: [String: PixelBuffer] = [:]
        func decode(_ path: String) throws -> PixelBuffer {
            if let buffer = decoded[path] { return buffer }
            guard let bytes = entries[path] else { throw CodecError.damaged("missing layer source \(path)") }
            let buffer = try codec(path) { try pixels.decodePNG(bytes) }
            try checkSize(buffer.width, buffer.height, path)
            decoded[path] = buffer
            return buffer
        }
        // Depth first again, each list bottom to top: `rest` is popped from its end, the bottom of the stack.
        // Offsets are each within StackXML.maxOffset and at most maxDepth deep, so sums cannot overflow.
        var open: [(rest: [StackXML.Node], group: StackXML.Element?, x: Int, y: Int, built: [LayerNode])] = [(stack.nodes, nil, 0, 0, [])]
        var tree: [LayerNode] = []
        while let top = open.indices.last {
            let (x, y) = (open[top].x, open[top].y)
            switch open[top].rest.popLast() {
            case .layer(let layer)?:
                // the walk above has checked that every layer has a src.
                open[top].built.append(.pixels(PixelLayer(name: layer.name, pixels: try decode(layer.src ?? ""), x: x + layer.x,
                                                          y: y + layer.y, opacity: layer.opacity,
                                                          blendMode: layer.blendMode ?? .normal, isHidden: layer.isHidden)))
            case .stack(let group, let children)?:
                open.append((children, group, x + group.x, y + group.y, []))
            case nil:
                let done = open.removeLast()
                guard let group = done.group, top > 0 else { tree = done.built; continue }
                open[top - 1].built.append(.group(LayerGroup(name: group.name, children: done.built, opacity: group.opacity,
                                                             blendMode: group.blendMode, isHidden: group.isHidden)))
            }
        }
        let composite = try entries[merged].map { _ in try decode(merged) }
        guard composite.map({ $0.width == stack.width && $0.height == stack.height }) ?? true else {
            throw CodecError.damaged("mergedimage.png is not the canvas size")
        }
        return LayeredImage(width: stack.width, height: stack.height, nodes: tree,
                            composite: composite, bitsPerChannel: 8, profile: nil)
    }

    /// The pixel count of the PNG's IHDR, within `maxSide` and
    /// `PixelBuffer.maxPixels`; `damaged` without a PNG signature and IHDR.
    static func pngPixels(_ bytes: Data, _ path: String) throws -> Int {
        let header = [UInt8](bytes.prefix(24))
        guard header.count == 24, header.starts(with: pngSignature), header[12..<16].elementsEqual("IHDR".utf8) else {
            throw CodecError.damaged("\(path) has no PNG header")
        }
        let side = { (at: Int) in header[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } }
        let width = side(16), height = side(20)
        try checkSize(width, height, path)
        // checkSize keeps width x height within PixelBuffer.maxPixels.
        return width * height
    }

    static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// `body`'s result; an error that is not a `CodecError` becomes `pixelCodec` naming `path`.
    static func codec<T>(_ path: String, _ body: () throws -> T) throws -> T {
        do { return try body() } catch let error as CodecError { throw error } catch {
            throw CodecError.pixelCodec("\(path): \(error)")
        }
    }

    static func checkSize(_ width: Int, _ height: Int, _ path: String) throws {
        guard (1...maxSide).contains(width), (1...maxSide).contains(height),
              (try? PixelBuffer.validatedSize(width: width, height: height)) != nil else {
            throw CodecError.tooLarge("\(path) is \(width)x\(height)")
        }
    }

    /// Saves an image as `.ora` bytes, encoding each layer's PNG with `pixels`.
    /// `extra` holds app entries stored beside the standard ones, keyed by path
    /// (for example `photo/document.json`); one that collides with a standard
    /// entry throws `unsupported`. Throws a `CodecError`, before encoding
    /// anything, for an image the format cannot hold (see OpenRasterWrite.swift):
    /// a profile, a missing composite, a mask or clipping. A group's `isOpen`
    /// is not kept; it reopens open.
    public static func write(_ image: LayeredImage, pixels: any PixelCodec,
                             extra: [String: Data] = [:]) throws -> Data {
        try encode(image, pixels: pixels, extra: extra)
    }
}
