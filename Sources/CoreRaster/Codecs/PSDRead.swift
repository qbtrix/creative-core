// PSDRead.swift: opens 8-bit RGB and grayscale PSD files, from the published
// PSD file format specification. Sections in file order: header, colour mode
// data and image resources (skipped by length; the profile stays nil), the
// layer and mask section (records bottom to top, then each record's channels,
// raw or RLE), and the merged image, which fills `composite`.
// Invariants a reader must keep:
// - Every read goes through `ByteReader`; a size from the file is checked
//   against `PSD.maxSide`, `PSD.maxLayers` or the bytes left before anything
//   is allocated from it; the canvas, layer and mask bounds together stay
//   within `PSD.maxTotalPixels` before any channel decodes; and a pixel
//   buffer is only built from planes that were fully decoded.
// - Records run bottom to top: a bounding divider opens a group and the
//   folder record above it closes it, carrying the group's attributes.
//   Unbalanced dividers throw `damaged`.
// - Colour becomes premultiplied linear light through the sRGB curve; mask
//   and opacity bytes are fractions of 255.
import CoreColor
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension PSD {
    /// Opens PSD bytes. Throws a `CodecError` for damaged or unsupported files.
    /// A blend key this reader does not know opens as `.normal`.
    public static func read(_ data: Data) throws -> LayeredImage {
        var reader = ByteReader(data)
        let header = try PSDHeader(&reader)
        try reader.skip(try reader.length32()) // colour mode data
        try reader.skip(try reader.length32()) // image resources
        var section = try reader.reader(try reader.length32())
        let (nodes, mergedAlpha) = try readLayers(&section, header)
        let planes = try readPlanes(&reader, count: header.channels, width: header.width, height: header.height)
        let alpha = mergedAlpha && planes.count > header.colorChannels ? planes[header.colorChannels] : nil
        let composite = try buffer(width: header.width, height: header.height,
                                   color: Array(planes.prefix(header.colorChannels)), alpha: alpha)
        return LayeredImage(width: header.width, height: header.height, nodes: nodes, composite: composite)
    }

    /// The layer tree, and whether the merged image's first alpha channel is its transparency.
    private static func readLayers(_ section: inout ByteReader, _ header: PSDHeader) throws -> ([LayerNode], Bool) {
        guard !section.isAtEnd else { return ([], false) }
        var info = try section.reader(try section.length32())
        guard !info.isAtEnd else { return ([], false) }
        let count = Int(try info.i16())
        let mergedAlpha = count < 0
        guard abs(count) <= PSD.maxLayers else { throw CodecError.tooLarge("\(abs(count)) layers") }
        let records = try (0..<abs(count)).map { _ in try PSDLayerRecord(&info) }
        var pixels = header.width * header.height
        for record in records {
            pixels = try ByteReader.adding(pixels, try record.rect.area)
            pixels = try ByteReader.adding(pixels, try record.mask?.rect.area ?? 0)
        }
        try PSDHeader.checkBudget(pixels)
        let opens: Set<UInt32> = [3], closes: Set<UInt32> = [1, 2]
        var current: [LayerNode] = [], parents: [[LayerNode]] = []
        for record in records {
            var planes: [Int16: [UInt8]] = [:]
            for channel in record.channels {
                var data = try info.reader(channel.length)
                let rect = channel.id == -2 ? record.mask?.rect ?? .empty : record.rect
                if channel.id >= -2, Int(channel.id) < header.colorChannels {
                    planes[channel.id] = try readPlanes(&data, count: 1, width: rect.width, height: rect.height).first
                }
            }
            if let type = record.section, opens.contains(type) {
                parents.append(current)
                current = []
                continue
            }
            let node: LayerNode
            if let type = record.section, closes.contains(type) {
                guard let parent = parents.popLast() else {
                    throw CodecError.damaged("group \"\(record.name)\" closes with no divider below it")
                }
                let key = record.sectionKey ?? record.blendKey
                node = .group(LayerGroup(name: record.name, children: current, opacity: record.opacityFraction,
                                         blendMode: key == "pass" ? nil : blendMode(key),
                                         isHidden: record.isHidden, isOpen: type == 1))
                current = parent
            } else {
                node = .pixels(try pixelLayer(record, planes, colorChannels: header.colorChannels))
            }
            current.append(node)
        }
        guard parents.isEmpty else { throw CodecError.damaged("unbalanced group dividers") }
        return (current, mergedAlpha)
    }

    private static func pixelLayer(_ record: PSDLayerRecord, _ planes: [Int16: [UInt8]],
                                   colorChannels: Int) throws -> PixelLayer {
        let rect = record.rect
        var pixels = try PixelBuffer(width: 1, height: 1)
        if rect.width > 0, rect.height > 0 {
            let color = try (0..<colorChannels).map { c in
                guard let plane = planes[Int16(c)] else { throw CodecError.damaged("layer \"\(record.name)\" lacks channel \(c)") }
                return plane
            }
            pixels = try buffer(width: rect.width, height: rect.height, color: color, alpha: planes[-1])
        }
        var mask: PlacedMask?
        if let m = record.mask, m.rect.width > 0, m.rect.height > 0 {
            let count = try pixelCount(m.rect.width, m.rect.height)
            guard let plane = planes[-2], plane.count == count else { throw CodecError.damaged("layer \"\(record.name)\" lacks its mask") }
            mask = PlacedMask(mask: Mask(checkedWidth: m.rect.width, height: m.rect.height, storage: plane.map { Float($0) / 255 }),
                              x: m.rect.left, y: m.rect.top, defaultCoverage: Float(m.color) / 255, isDisabled: m.flags & 0x02 != 0)
        }
        return PixelLayer(name: record.name, pixels: pixels, x: rect.left, y: rect.top, opacity: record.opacityFraction,
                          blendMode: blendMode(record.blendKey), isHidden: record.isHidden,
                          clipsToBelow: record.clipping != 0, mask: mask)
    }

    /// `count` planes of `width` x `height` bytes behind one compression value:
    /// 0 raw, 1 RLE (every row's byte count first, then the PackBits rows).
    private static func readPlanes(_ reader: inout ByteReader, count: Int, width: Int, height: Int) throws -> [[UInt8]] {
        switch try reader.u16() {
        case 0:
            let size = try ByteReader.multiplying(width, height)
            return try (0..<count).map { _ in try reader.bytes(size) }
        case 1:
            guard width > 0, height > 0 else { return Array(repeating: [], count: count) }
            let rows = try ByteReader.multiplying(count, height)
            guard try ByteReader.multiplying(rows, 2) <= reader.remaining else {
                throw CodecError.damaged("\(rows) RLE row counts pass the end")
            }
            let lengths = try (0..<rows).map { _ in Int(try reader.u16()) }
            var planes: [[UInt8]] = [], plane: [UInt8] = []
            for (index, length) in lengths.enumerated() {
                var row = try reader.reader(length)
                plane += try PackBits.decode(&row, count: width)
                if (index + 1) % height == 0 { planes.append(plane); plane = [] }
            }
            return planes
        case 2, 3: throw CodecError.unsupported("zip-compressed channel")
        case let other: throw CodecError.damaged("compression \(other)")
        }
    }

    /// Premultiplied linear pixels from encoded colour planes (one plane is grey) and an optional alpha plane.
    private static func buffer(width: Int, height: Int, color: [[UInt8]], alpha: [UInt8]?) throws -> PixelBuffer {
        let count = try pixelCount(width, height)
        guard !color.isEmpty, color.allSatisfy({ $0.count == count }), (alpha?.count ?? count) == count else {
            throw CodecError.damaged("planes do not fill \(width)x\(height)")
        }
        let planes = color.count == 1 ? [color[0], color[0], color[0]] : color
        var storage = [Float](repeating: 0, count: count * 4)
        for i in 0..<count {
            let a = alpha.map { Float($0[i]) / 255 } ?? 1
            for c in 0..<3 { storage[i * 4 + c] = linear[Int(planes[c][i])] * a }
            storage[i * 4 + 3] = a
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: storage)
    }

    private static func pixelCount(_ width: Int, _ height: Int) throws -> Int {
        do { return try PixelBuffer.validatedSize(width: width, height: height) } catch {
            throw CodecError.tooLarge("\(width)x\(height) pixels")
        }
    }

    /// Encoded 8-bit sRGB to linear light.
    static let linear: [Float] = (0..<256).map { Float(TransferCurve.decode(Double($0) / 255)) }

    static let blendModes: [String: BlendMode] = [
        "norm": .normal, "mul ": .multiply, "scrn": .screen, "over": .overlay, "dark": .darken, "lite": .lighten,
        "div ": .colorDodge, "idiv": .colorBurn, "hLit": .hardLight, "sLit": .softLight, "diff": .difference,
        "smud": .exclusion, "hue ": .hue, "sat ": .saturation, "colr": .color, "lum ": .luminosity]

    /// A blend key's mode; a key this reader does not know opens as normal.
    private static func blendMode(_ key: String) -> BlendMode { blendModes[key] ?? .normal }
}

/// The file header: canvas size, channel count and how many of them are colour.
private struct PSDHeader {
    let channels: Int, width: Int, height: Int, colorChannels: Int

    init(_ r: inout ByteReader) throws {
        guard try r.bytes(4) == Array("8BPS".utf8) else { throw CodecError.notThisFormat }
        switch try r.u16() {
        case 1: break
        case 2: throw CodecError.unsupported("large document format")
        case let version: throw CodecError.damaged("version \(version)")
        }
        try r.skip(6)
        channels = Int(try r.u16())
        guard (1...56).contains(channels) else { throw CodecError.damaged("\(channels) channels") }
        height = try PSDRect.side(try r.length32())
        width = try PSDRect.side(try r.length32())
        guard height > 0, width > 0 else { throw CodecError.damaged("an empty canvas") }
        try Self.checkBudget(width * height)
        switch try r.u16() {
        case 8: break
        case let depth: throw CodecError.unsupported("\(depth)-bit channels")
        }
        switch try r.u16() {
        case 1: colorChannels = 1
        case 3: colorChannels = 3
        case let mode: throw CodecError.unsupported("colour mode \(mode)")
        }
        guard channels >= colorChannels else { throw CodecError.damaged("\(channels) channels for colour mode") }
    }

    /// Throws before decoding when the canvas, layers and masks hold more than `PSD.maxTotalPixels`.
    static func checkBudget(_ pixels: Int) throws {
        guard pixels <= PSD.maxTotalPixels else { throw CodecError.tooLarge("\(pixels) pixels over \(PSD.maxTotalPixels)") }
    }
}

/// Top, left, bottom, right as stored; sides are checked against `PSD.maxSide`.
private struct PSDRect {
    var top = 0, left = 0, bottom = 0, right = 0
    static let empty = PSDRect()
    var width: Int { right - left }
    var height: Int { bottom - top }
    var area: Int { get throws { try ByteReader.multiplying(width, height) } }

    init() {}

    init(_ r: inout ByteReader) throws {
        (top, left, bottom, right) = (Int(try r.i32()), Int(try r.i32()), Int(try r.i32()), Int(try r.i32()))
        guard bottom >= top, right >= left else { throw CodecError.damaged("bounds \(top), \(left), \(bottom), \(right)") }
        _ = try Self.side(width)
        _ = try Self.side(height)
    }

    static func side(_ side: Int) throws -> Int {
        guard side <= PSD.maxSide else { throw CodecError.tooLarge("side \(side) over \(PSD.maxSide)") }
        return side
    }
}

/// One layer record as stored, before its channel data.
private struct PSDLayerRecord {
    var rect: PSDRect, channels: [(id: Int16, length: Int)]
    var blendKey: String, opacity: UInt8, clipping: UInt8, flags: UInt8
    var mask: (rect: PSDRect, color: UInt8, flags: UInt8)?
    var name: String
    /// The `lsct` section type (1 open folder, 2 closed folder, 3 bounding divider) and its blend key.
    var section: UInt32?, sectionKey: String?

    var opacityFraction: Float { Float(opacity) / 255 }
    var isHidden: Bool { flags & 0x02 != 0 }

    init(_ r: inout ByteReader) throws {
        rect = try PSDRect(&r)
        let channelCount = Int(try r.u16())
        guard channelCount <= 56 else { throw CodecError.damaged("\(channelCount) layer channels") }
        channels = try (0..<channelCount).map { _ in (try r.i16(), try r.length32()) }
        blendKey = try Self.key(&r)
        (opacity, clipping, flags) = (try r.u8(), try r.u8(), try r.u8())
        try r.skip(1)
        var extra = try r.reader(try r.length32())
        var maskData = try extra.reader(try extra.length32())
        mask = maskData.isAtEnd ? nil : (try PSDRect(&maskData), try maskData.u8(), try maskData.u8())
        try extra.skip(try extra.length32()) // blending ranges
        let nameLength = Int(try extra.u8())
        name = String(decoding: try extra.bytes(nameLength), as: UTF8.self)
        try extra.skip(3 - nameLength % 4) // the Pascal string pads to a multiple of 4
        while extra.remaining >= 12 {
            let key = try Self.key(&extra)
            var block = try extra.reader(try extra.length32())
            if key == "luni" {
                let units = try block.length32()
                guard try ByteReader.multiplying(units, 2) <= block.remaining else { throw CodecError.damaged("a Unicode name passes its block") }
                name = String(decoding: try (0..<units).map { _ in try block.u16() }, as: UTF16.self)
            } else if key == "lsct" {
                section = try block.u32()
                if block.remaining >= 8 { sectionKey = try Self.key(&block) }
            }
        }
    }

    /// A four-byte key after its `8BIM` (or `8B64`) signature.
    private static func key(_ r: inout ByteReader) throws -> String {
        let signature = String(decoding: try r.bytes(4), as: UTF8.self)
        guard signature == "8BIM" || signature == "8B64" else { throw CodecError.damaged("signature \(signature)") }
        return String(decoding: try r.bytes(4), as: UTF8.self)
    }
}
