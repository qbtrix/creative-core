// RasterError.swift: the error type of CoreRaster, the shared raster module
// (pixel buffers, compositing, image operations). CoreRaster is Linux-safe,
// Foundation only, and depends only on CoreColor. Every non-codec API in this
// module throws this, `PixelBuffer.converted(from:to:)` included. The codecs
// under Codecs/ (`PSD`, `OpenRaster`, `ZipStore`, `PixelCodec`, `PNG`, `JPEG`,
// `Inflate`) throw `CodecError` instead, declared in Codecs/LayeredImage.swift.
public enum RasterError: Error, Equatable, Sendable {
    /// A size, index or parameter is out of range, or a buffer is too large.
    case invalid(String)
}
