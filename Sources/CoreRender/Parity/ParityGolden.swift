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
    public let width: Int, height: Int, colorSpace: ColorSpace, tolerance: ParityTolerance
}

/// One golden: its header and its `width * height * 4` display bytes.
public struct ParityGolden: Equatable, Sendable {
    public let header: ParityGoldenHeader
    public let bytes: [UInt8]

    public init(_ buffer: PixelBuffer, colorSpace: ColorSpace = .sRGB, tolerance: ParityTolerance) throws {
        header = ParityGoldenHeader(width: buffer.width, height: buffer.height, colorSpace: colorSpace,
                                    tolerance: tolerance)
        bytes = try ParityHarness.raster { try buffer.rgba8(colorSpace: colorSpace) }
    }

    /// Throws for an undecodable header, a size `validatedSize` rejects (it checks overflow), a
    /// non-display color space, a negative or non-finite linear tolerance, or the wrong byte count.
    public init(header json: Data, bytes data: Data) throws {
        guard let header = try? JSONDecoder().decode(ParityGoldenHeader.self, from: json) else {
            throw RenderError.raster("golden header does not decode")
        }
        let pixels = try ParityHarness.raster { try PixelBuffer.validatedSize(width: header.width, height: header.height) }
        guard PixelBuffer.displayColorSpaces.contains(header.colorSpace),
              header.tolerance.linear.isFinite, header.tolerance.linear >= 0 else {
            throw RenderError.raster("golden header has a bad color space or tolerance")
        }
        guard data.count == pixels * 4 else {
            throw RenderError.raster("golden has \(data.count) bytes; its header needs \(pixels * 4)")
        }
        (self.header, bytes) = (header, [UInt8](data))
    }

    /// The golden as a linear premultiplied buffer, for `compare`.
    public func buffer() throws -> PixelBuffer {
        try ParityHarness.raster { try PixelBuffer(rgba8: bytes, width: header.width, height: header.height,
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
    public static func read(from root: URL, op: RenderOp, name: String) throws -> ParityGolden {
        let (bytesURL, headerURL) = try urls(root: root, op: op, name: name)
        guard let header = try? Data(contentsOf: headerURL), let bytes = try? Data(contentsOf: bytesURL) else {
            throw RenderError.raster("golden \(op.rawValue)/\(name) not read")
        }
        return try ParityGolden(header: header, bytes: bytes)
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
