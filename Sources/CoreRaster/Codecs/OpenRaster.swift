// OpenRaster.swift: the OpenRaster (.ora) codec's entry points, from the
// published OpenRaster spec: a stored-entry zip with `mimetype`, `stack.xml`
// and one PNG per layer through the injected `PixelCodec`. Reading checks the
// `mimetype`, parses `stack.xml` with StackXML, turns its top-first stacks into
// bottom-to-top nodes (nested stacks become groups, stack offsets add to their
// layers'), sums every `src` and `mergedimage.png` IHDR within
// `maxTotalPixels`, then decodes each once. ORA carries no ICC
// profile, so `profile` is nil. Write lands in a later task and throws
// `CodecError.unsupported("not built")` until then.
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
        func collect(_ list: [StackXML.Node]) throws {
            for node in list {
                switch node {
                case .layer(let layer):
                    guard let src = layer.src else { throw CodecError.damaged("layer \(layer.name) has no src") }
                    guard used.insert(src).inserted else { throw CodecError.damaged("layer source \(src) repeats") }
                    sources.append(src)
                case .stack(_, let children): try collect(children)
                }
            }
        }
        try collect(stack.nodes)
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
            let buffer: PixelBuffer
            do { buffer = try pixels.decodePNG(bytes) } catch let error as CodecError { throw error } catch {
                throw CodecError.pixelCodec("\(path): \(error)")
            }
            try checkSize(buffer.width, buffer.height, path)
            decoded[path] = buffer
            return buffer
        }
        // Offsets are each within StackXML.maxOffset and at most maxDepth deep, so sums cannot overflow.
        func nodes(_ list: [StackXML.Node], x: Int, y: Int) throws -> [LayerNode] {
            try list.reversed().map { node in
                switch node {
                case .layer(let layer):
                    // collect has checked that every layer has a src.
                    return .pixels(PixelLayer(name: layer.name, pixels: try decode(layer.src ?? ""), x: x + layer.x, y: y + layer.y,
                                              opacity: layer.opacity, blendMode: layer.blendMode ?? .normal,
                                              isHidden: layer.isHidden))
                case .stack(let group, let children):
                    return .group(LayerGroup(name: group.name, children: try nodes(children, x: x + group.x, y: y + group.y),
                                             opacity: group.opacity, blendMode: group.blendMode, isHidden: group.isHidden))
                }
            }
        }
        let tree = try nodes(stack.nodes, x: 0, y: 0)
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

    static func checkSize(_ width: Int, _ height: Int, _ path: String) throws {
        guard (1...maxSide).contains(width), (1...maxSide).contains(height),
              (try? PixelBuffer.validatedSize(width: width, height: height)) != nil else {
            throw CodecError.tooLarge("\(path) is \(width)x\(height)")
        }
    }

    /// Saves an image as `.ora` bytes, encoding each layer's PNG with `pixels`.
    /// `extra` holds app entries stored beside the standard ones, keyed by path
    /// (for example `photo/document.json`).
    public static func write(_ image: LayeredImage, pixels: any PixelCodec,
                             extra: [String: Data] = [:]) throws -> Data {
        throw CodecError.unsupported("not built")
    }
}
