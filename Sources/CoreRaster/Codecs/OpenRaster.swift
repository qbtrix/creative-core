// OpenRaster.swift: the OpenRaster (.ora) codec's entry points, from the
// published OpenRaster spec: a stored-entry zip with `mimetype`, `stack.xml`
// and one PNG per layer through the injected `PixelCodec`. Reading checks the
// `mimetype`, parses `stack.xml` with StackXML, turns its top-first stacks into
// bottom-to-top nodes (nested stacks become groups, stack offsets add to their
// layers'), and decodes each `src` and `mergedimage.png`. ORA carries no ICC
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
    /// The most layers and stacks one `stack.xml` may hold, as for PSD.
    public static let maxLayers = PSD.maxLayers
    /// The most nested `<stack>` levels `stack.xml` may have.
    public static let maxDepth = 256

    /// Opens `.ora` bytes, decoding each layer's PNG with `pixels`.
    /// Throws `notThisFormat` without the OpenRaster `mimetype`, `damaged`
    /// for a missing `stack.xml`, a missing or repeated layer source (naming
    /// it) or a `mergedimage.png` other than the canvas size, `tooLarge` for
    /// an image over `maxSide` or `PixelBuffer.maxPixels` (read from a PNG's
    /// IHDR before decoding, and checked again after), and whatever
    /// `ZipStore`, `StackXML` and `pixels` throw.
    public static func read(_ data: Data, pixels: any PixelCodec) throws -> LayeredImage {
        let entries = try ZipStore.entries(data)
        guard entries["mimetype"] == Data("image/openraster".utf8) else { throw CodecError.notThisFormat }
        guard let xml = entries["stack.xml"] else { throw CodecError.damaged("no stack.xml") }
        let stack = try StackXML.parse(xml)
        var used: Set<String> = []
        func decode(_ path: String) throws -> PixelBuffer {
            guard let bytes = entries[path] else { throw CodecError.damaged("missing layer source \(path)") }
            if bytes.starts(with: pngSignature) {
                let header = [UInt8](bytes.prefix(24))
                guard header.count == 24 else { throw CodecError.damaged("PNG header of \(path)") }
                let side = { (at: Int) in header[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } }
                try checkSize(side(16), side(20), path)
            }
            let buffer: PixelBuffer
            do { buffer = try pixels.decodePNG(bytes) } catch let error as CodecError { throw error } catch {
                throw CodecError.pixelCodec("\(path): \(error)")
            }
            try checkSize(buffer.width, buffer.height, path)
            return buffer
        }
        // Offsets are each within StackXML.maxOffset and at most maxDepth deep, so sums cannot overflow.
        func nodes(_ list: [StackXML.Node], x: Int, y: Int) throws -> [LayerNode] {
            try list.reversed().map { node in
                switch node {
                case .layer(let layer):
                    guard let src = layer.src else { throw CodecError.damaged("layer \(layer.name) has no src") }
                    guard used.insert(src).inserted else { throw CodecError.damaged("layer source \(src) repeats") }
                    return .pixels(PixelLayer(name: layer.name, pixels: try decode(src), x: x + layer.x, y: y + layer.y,
                                              opacity: layer.opacity, blendMode: layer.blendMode ?? .normal,
                                              isHidden: layer.isHidden))
                case .stack(let group, let children):
                    return .group(LayerGroup(name: group.name, children: try nodes(children, x: x + group.x, y: y + group.y),
                                             opacity: group.opacity, blendMode: group.blendMode, isHidden: group.isHidden))
                }
            }
        }
        let composite = try entries["mergedimage.png"].map { _ in try decode("mergedimage.png") }
        guard composite.map({ $0.width == stack.width && $0.height == stack.height }) ?? true else {
            throw CodecError.damaged("mergedimage.png is not the canvas size")
        }
        return LayeredImage(width: stack.width, height: stack.height, nodes: try nodes(stack.nodes, x: 0, y: 0),
                            composite: composite, bitsPerChannel: 8, profile: nil)
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
