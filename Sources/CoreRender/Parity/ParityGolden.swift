// ParityGolden.swift: a golden on disk, `<root>/<op>/<case>.rgba8` (display
// bytes, row-major, straight alpha) beside `<case>.json`. Golden files are
// untrusted: every check throws `RenderError.raster` and never traps.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreColor
import CoreRaster

/// A golden file's JSON header; `colorSpace` is a display space.
public struct ParityGoldenHeader: Codable, Equatable, Sendable {
    /// The image size in pixels.
    public let width: Int, height: Int
    /// The display space the bytes are encoded in (sRGB or Display P3).
    public let colorSpace: ColorSpace
    /// The tolerance the golden was cut with, for comparing against it.
    public let tolerance: ParityTolerance
}

/// One golden: its header and its `width * height * 4` display bytes.
public struct ParityGolden: Equatable, Sendable {
    /// Size, color space and tolerance.
    public let header: ParityGoldenHeader
    /// `width * height * 4` display bytes, row-major, straight alpha.
    public let bytes: [UInt8]

    /// A golden cut from `buffer`, encoded in `colorSpace`. Throws
    /// `RenderError.raster` when CoreRaster cannot encode it (not a display space).
    public init(_ buffer: PixelBuffer, colorSpace: ColorSpace = .sRGB, tolerance: ParityTolerance) throws {
        header = ParityGoldenHeader(width: buffer.width, height: buffer.height, colorSpace: colorSpace,
                                    tolerance: tolerance)
        bytes = try RenderError.mapping { try buffer.rgba8(colorSpace: colorSpace) }
    }

    /// Throws for an undecodable header, a size `validatedSize` rejects (it checks overflow), a
    /// non-display color space, a negative or non-finite linear tolerance, or the wrong byte count.
    public init(header json: Data, bytes data: Data) throws {
        let header: ParityGoldenHeader
        do { header = try JSONDecoder().decode(ParityGoldenHeader.self, from: json) } catch {
            throw RenderError.raster("golden header does not decode: \(error)")
        }
        let pixels = try RenderError.mapping { try PixelBuffer.validatedSize(width: header.width, height: header.height) }
        guard PixelBuffer.displayColorSpaces.contains(header.colorSpace) else {
            throw RenderError.raster("golden color space \(header.colorSpace) is not a display space")
        }
        guard header.tolerance.linear.isFinite, header.tolerance.linear >= 0 else {
            throw RenderError.raster("golden tolerance.linear \(header.tolerance.linear) must be finite and >= 0")
        }
        guard data.count == pixels * 4 else {
            throw RenderError.raster("golden has \(data.count) bytes; its header needs \(pixels * 4)")
        }
        (self.header, bytes) = (header, [UInt8](data))
    }

    /// The golden as a linear premultiplied buffer, to inspect or crop. Its values are
    /// off by up to half a display level, so check a result against the golden with
    /// `ParityHarness.compare(golden:_:)`, not by comparing this buffer in linear.
    public func buffer() throws -> PixelBuffer {
        try RenderError.mapping { try PixelBuffer(rgba8: bytes, width: header.width, height: header.height,
                                                   colorSpace: header.colorSpace) }
    }

    /// Writes `<root>/<op>/<name>.rgba8` and `<name>.json`, creating the folder.
    public func write(to root: URL, op: RenderOp, name: String) throws {
        let (bytesURL, headerURL) = try Self.urls(root: root, op: op, name: name)
        do {
            let folder = bytesURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(bytes).write(to: bytesURL)
            try JSONEncoder().encode(header).write(to: headerURL)
        } catch { throw RenderError.raster("golden \(op.rawValue)/\(name) not written: \(error)") }
    }

    /// Reads what `write(to:op:name:)` wrote, validated as `init(header:bytes:)`.
    /// A file that cannot be read throws `RenderError.raster` with its path and the I/O error.
    public static func read(from root: URL, op: RenderOp, name: String) throws -> ParityGolden {
        let (bytesURL, headerURL) = try urls(root: root, op: op, name: name)
        return try ParityGolden(header: contents(of: headerURL), bytes: contents(of: bytesURL))
    }

    private static func contents(of url: URL) throws -> Data {
        do { return try Data(contentsOf: url) } catch {
            throw RenderError.raster("golden \(url.path(percentEncoded: false)) not read: \(error)")
        }
    }

    /// The files of golden `name`, which must be ASCII letters, digits and `-`.
    private static func urls(root: URL, op: RenderOp, name: String) throws -> (URL, URL) {
        guard !name.isEmpty, name.allSatisfy({ $0 == "-" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }) else {
            throw RenderError.raster("golden name \"\(name)\" must be letters, digits and -")
        }
        let folder = root.appendingPathComponent(op.rawValue, isDirectory: true)
        return (folder.appendingPathComponent(name + ".rgba8"), folder.appendingPathComponent(name + ".json"))
    }
}
