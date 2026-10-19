// MaskFromBuffer.swift: a mask read from a buffer's alpha or luminance (stub).

extension Mask {
    /// Stub: an empty mask the buffer's size.
    public init(from buffer: PixelBuffer, _ source: MatteSource, inverted: Bool = false) throws {
        try self.init(width: buffer.width, height: buffer.height)
    }
}
