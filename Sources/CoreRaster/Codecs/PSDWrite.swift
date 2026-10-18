// PSDWrite.swift: saves a `LayeredImage` as an 8- or 16-bit RGB PSD (grayscale
// when its profile is gray), from the
// published PSD file format specification, so that `PSD.read` reopens it
// equal. Sections in file order: header, empty colour mode data, image
// resources (the profile as resource 1039), the layer and mask section (records bottom to top, then each
// record's channels), and the merged image from `composite` (or, when that is
// nil, a preview flattened from the visible layers' pixels, opacity and blend
// mode, without masks, clipping or group blending).
// Invariants a writer must keep:
// - Nothing is written until the whole image is validated: bits per channel 8
//   or 16, a profile the ICC writer takes, with a gray one every layer and the
//   composite neutral (equal stored samples), every opacity and mask default
//   finite in 0...1, every layer and mask side within `PSD.maxSide` and its
//   bounds within Int32, the canvas and every layer and mask within
//   `PSD.maxTotalPixels`, at most `PSD.maxLayers` records. Each failure
//   throws a `CodecError`; all size arithmetic is checked.
// - A group is a bounding divider record, its children, then the folder
//   record carrying its name, opacity, blend key (`pass` for nil), hidden
//   flag and open or closed state.
// - Every channel is RLE. Colour is the exact inverse of the reader's: alpha
//   and mask samples are fractions of 255 or 65535 rounded to nearest, and each
//   colour sample is the one whose decoded sRGB value, times that alpha, is nearest.
import CoreColor
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension PSD {
    /// The bytes `write` returns: validates first, then writes.
    static func encode(_ image: LayeredImage) throws -> Data {
        let depth = try PSDDepth(bits: image.bitsPerChannel)
        let resources = try imageResources(image.profile)
        guard image.width >= 1, image.height >= 1 else { throw CodecError.unsupported("a \(image.width)x\(image.height) canvas") }
        guard image.width <= maxSide, image.height <= maxSide else {
            throw CodecError.tooLarge("canvas \(image.width)x\(image.height) over \(maxSide)")
        }
        if let c = image.composite, c.width != image.width || c.height != image.height {
            throw CodecError.unsupported("a \(c.width)x\(c.height) composite on a \(image.width)x\(image.height) canvas")
        }
        let items = try layerItems(image.nodes)
        var pixels = try ByteReader.multiplying(image.width, image.height)
        let records = try items.map { item in
            let record = try PSDOutRecord(item)
            pixels = try ByteReader.adding(pixels, try record.area)
            guard pixels <= maxTotalPixels else { throw CodecError.tooLarge("\(pixels) pixels over \(maxTotalPixels)") }
            return record
        }
        let composite = try image.composite ?? flattened(items, width: image.width, height: image.height)
        let gray = image.profile?.isGray == true
        let channels = try records.map { try $0.channelData(depth, gray: gray) }
        let planes = try depth.colorPlanes(composite, gray: gray, "the composite")
        let colors = gray ? 1 : 3

        var w = PSDByteWriter()
        w.ascii("8BPS")
        w.u16(1)
        w.bytes += [0, 0, 0, 0, 0, 0]
        w.u16(UInt16(records.isEmpty ? colors : colors + 1))
        try w.length(image.height)
        try w.length(image.width)
        w.u16(UInt16(depth.rawValue))
        w.u16(gray ? 1 : 3) // grayscale or RGB
        w.u32(0) // colour mode data
        try w.length(resources.count)
        w.bytes += resources
        try w.sized { section in
            try section.sized(pad: 2) { info in
                info.i16(Int16(truncatingIfNeeded: -records.count)) // negative: the merged alpha is transparency
                for (record, data) in zip(records, channels) { try record.write(data, into: &info) }
                for data in channels { for (_, bytes) in data { info.bytes += bytes } }
            }
            section.u32(0) // global layer mask info
        }
        let merged = Array(planes.prefix(colors)) + (records.isEmpty ? [] : [planes[colors]])
        w.bytes += try rle(merged, width: image.width * depth.bytes)
        return Data(w.bytes)
    }

    /// One record's source, bottom to top: a pixel layer, or a group's divider or folder.
    enum LayerItem { case layer(PixelLayer), divider(LayerGroup), folder(LayerGroup) }

    /// The tree in record order, walked without recursion; more than `maxLayers` records throws.
    private static func layerItems(_ nodes: [LayerNode]) throws -> [LayerItem] {
        var items: [LayerItem] = []
        var stack: [(nodes: [LayerNode], next: Int, group: LayerGroup?)] = [(nodes, 0, nil)]
        while var top = stack.popLast() {
            if top.next < top.nodes.count {
                let node = top.nodes[top.next]
                top.next += 1
                stack.append(top)
                switch node {
                case .pixels(let layer): items.append(.layer(layer))
                case .group(let group): items.append(.divider(group)); stack.append((group.children, 0, group))
                }
            } else if let group = top.group {
                items.append(.folder(group))
            }
            guard items.count <= maxLayers else { throw CodecError.tooLarge("more than \(maxLayers) layer records") }
        }
        return items
    }

    /// The visible layers composited in order, for a file whose image has no composite.
    private static func flattened(_ items: [LayerItem], width: Int, height: Int) throws -> PixelBuffer {
        do {
            var canvas = try PixelBuffer(width: width, height: height)
            var groups: [(opacity: Float, hidden: Bool)] = []
            var scale: (opacity: Float, hidden: Bool) = (1, false)
            for item in items {
                switch item {
                case .divider(let group):
                    groups.append(scale)
                    scale = (scale.opacity * group.opacity, scale.hidden || group.isHidden)
                case .folder: scale = groups.popLast() ?? (1, false)
                case .layer(let layer):
                    guard !layer.isHidden, !scale.hidden else { continue }
                    try canvas.composite(layer.pixels, x: layer.x, y: layer.y, mode: layer.blendMode,
                                         opacity: layer.opacity * scale.opacity)
                }
            }
            return canvas
        } catch let error as CodecError { throw error } catch {
            throw CodecError.unsupported("flattening the layers: \(error)")
        }
    }

    /// `planes` (each `width` wide) behind one RLE compression value: every row's byte count, then the rows.
    static func rle(_ planes: [[UInt8]], width: Int) throws -> [UInt8] {
        var counts = PSDByteWriter(), rows: [UInt8] = []
        counts.u16(1)
        for plane in planes {
            for start in stride(from: 0, to: plane.count, by: max(width, 1)) {
                let row = PackBits.encode(Array(plane[start..<min(start + width, plane.count)]))
                guard let count = UInt16(exactly: row.count) else { throw CodecError.tooLarge("an RLE row of \(row.count) bytes") }
                counts.u16(count)
                rows += row
            }
        }
        return counts.bytes + rows
    }

    /// A 0...1 value as a byte of 255ths, rounded to nearest; NaN and below 0 are 0.
    static func fraction(_ value: Float) -> UInt8 {
        let scaled = (value * 255).rounded()
        guard scaled > 0 else { return 0 }
        return scaled >= 255 ? 255 : UInt8(scaled)
    }

    /// A finite 0...1 attribute as a byte, or `unsupported` naming it.
    static func attributeByte(_ value: Float, _ what: String) throws -> UInt8 {
        guard (0...1).contains(value) else { throw CodecError.unsupported("\(what) \(value): must be finite in 0...1") }
        return fraction(value)
    }

    /// A blend mode's key, the inverse of the reader's table.
    static let blendKeys: [BlendMode: String] = Dictionary(blendModes.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
}

/// A big-endian byte sink, the writing counterpart of `ByteReader`.
struct PSDByteWriter {
    var bytes: [UInt8] = []
    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func u16(_ v: UInt16) { bytes += [UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)] }
    mutating func u32(_ v: UInt32) { u16(UInt16(truncatingIfNeeded: v >> 16)); u16(UInt16(truncatingIfNeeded: v)) }
    mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
    mutating func ascii(_ s: String) { bytes += Array(s.utf8) }
    /// A length as a big-endian UInt32, or `tooLarge` when it does not fit.
    mutating func length(_ n: Int) throws {
        guard let v = UInt32(exactly: n) else { throw CodecError.tooLarge("length \(n) over 32 bits") }
        u32(v)
    }
    /// What `body` writes, after its UInt32 length, padded to a multiple of `pad`.
    mutating func sized(pad: Int = 1, _ body: (inout PSDByteWriter) throws -> Void) throws {
        var inner = PSDByteWriter()
        try body(&inner)
        inner.bytes += Array(repeating: 0, count: (pad - inner.bytes.count % pad) % pad)
        try length(inner.bytes.count)
        bytes += inner.bytes
    }
}

/// Top, left, bottom, right in Int32, from a validated offset and size.
private struct PSDOutRect {
    var top: Int32 = 0, left: Int32 = 0, bottom: Int32 = 0, right: Int32 = 0
    var area = 0

    init() {}

    init(x: Int, y: Int, width: Int, height: Int, _ what: String) throws {
        guard width <= PSD.maxSide, height <= PSD.maxSide else { throw CodecError.tooLarge("\(what) \(width)x\(height) over \(PSD.maxSide)") }
        let r = try ByteReader.adding(x, width), b = try ByteReader.adding(y, height)
        guard let l32 = Int32(exactly: x), let t32 = Int32(exactly: y), let r32 = Int32(exactly: r), let b32 = Int32(exactly: b) else {
            throw CodecError.tooLarge("\(what) bounds \(x), \(y), \(r), \(b) pass Int32")
        }
        (top, left, bottom, right, area) = (t32, l32, b32, r32, try ByteReader.multiplying(width, height))
    }

    func write(into w: inout PSDByteWriter) { for v in [top, left, bottom, right] { w.i32(v) } }
}

/// One validated layer record, before its channels are encoded.
private struct PSDOutRecord {
    var rect = PSDOutRect(), layer: PixelLayer?
    var mask: (rect: PSDOutRect, color: UInt8, flags: UInt8)?
    var blendKey = "norm", opacity: UInt8 = 255, clipping: UInt8 = 0, flags: UInt8 = 0
    var name: String, section: (type: UInt32, key: String?)?

    var area: Int { get throws { try ByteReader.adding(rect.area, mask?.rect.area ?? 0) } }

    init(_ item: PSD.LayerItem) throws {
        switch item {
        case .divider:
            name = "</Layer group>"
            section = (3, nil)
        case .folder(let group):
            name = group.name
            blendKey = group.blendMode.flatMap { PSD.blendKeys[$0] } ?? "pass"
            opacity = try PSD.attributeByte(group.opacity, "opacity of \"\(group.name)\"")
            flags = group.isHidden ? 0x02 : 0
            section = (group.isOpen ? 1 : 2, blendKey)
        case .layer(let l):
            name = l.name
            layer = l
            rect = try PSDOutRect(x: l.x, y: l.y, width: l.pixels.width, height: l.pixels.height, "layer \"\(l.name)\"")
            blendKey = PSD.blendKeys[l.blendMode] ?? "norm"
            opacity = try PSD.attributeByte(l.opacity, "opacity of \"\(l.name)\"")
            clipping = l.clipsToBelow ? 1 : 0
            flags = l.isHidden ? 0x02 : 0
            if let m = l.mask {
                mask = (try PSDOutRect(x: m.x, y: m.y, width: m.mask.width, height: m.mask.height, "mask of \"\(l.name)\""),
                        try PSD.attributeByte(m.defaultCoverage, "mask default of \"\(l.name)\""), m.isDisabled ? 0x02 : 0)
            }
        }
    }

    /// Each channel's id and RLE bytes at `depth`: transparency, red, green, blue (or grey alone
    /// when `gray`), then the mask.
    func channelData(_ depth: PSDDepth, gray: Bool) throws -> [(id: Int16, bytes: [UInt8])] {
        let ids: [(Int16, Int)] = gray ? [(-1, 1), (0, 0)] : [(-1, 3), (0, 0), (1, 1), (2, 2)]
        guard let layer else { return try ids.map { ($0.0, try PSD.rle([], width: 0)) } }
        let planes = try depth.colorPlanes(layer.pixels, gray: gray, "layer \"\(layer.name)\"")
        let width = layer.pixels.width * depth.bytes
        var channels = try ids.map { (id: $0.0, bytes: try PSD.rle([planes[$0.1]], width: width)) }
        if let m = layer.mask?.mask {
            channels.append((-2, try PSD.rle([depth.maskPlane(m)], width: m.width * depth.bytes)))
        }
        return channels
    }

    func write(_ channels: [(id: Int16, bytes: [UInt8])], into w: inout PSDByteWriter) throws {
        rect.write(into: &w)
        w.u16(UInt16(truncatingIfNeeded: channels.count))
        for channel in channels {
            w.i16(channel.id)
            try w.length(channel.bytes.count)
        }
        w.ascii("8BIM" + blendKey)
        w.bytes += [opacity, clipping, flags, 0]
        try w.sized { extra in
            try extra.sized { data in
                guard let mask else { return }
                mask.rect.write(into: &data)
                data.bytes += [mask.color, mask.flags, 0, 0]
            }
            extra.u32(0) // blending ranges
            let pascal = name.unicodeScalars.prefix(255).map { $0.isASCII ? UInt8(truncatingIfNeeded: $0.value) : UInt8(ascii: "?") }
            extra.u8(UInt8(truncatingIfNeeded: pascal.count))
            extra.bytes += pascal + Array(repeating: 0, count: 3 - pascal.count % 4)
            extra.ascii("8BIMluni")
            try extra.sized { block in
                try block.length(name.utf16.count)
                for unit in name.utf16 { block.u16(unit) }
            }
            if let section {
                extra.ascii("8BIMlsct")
                try extra.sized { block in
                    block.u32(section.type)
                    if let key = section.key { block.ascii("8BIM" + key) }
                }
            }
        }
    }
}
