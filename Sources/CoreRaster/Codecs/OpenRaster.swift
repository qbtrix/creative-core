// OpenRaster.swift: the OpenRaster (.ora) codec's entry points, from the
// published OpenRaster spec: a stored-entry zip with `mimetype`, `stack.xml`
// and one PNG per layer through the injected `PixelCodec`. Read and write land
// in later tasks; until then both throw `CodecError.unsupported("not built")`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Reads and writes OpenRaster files as a `LayeredImage`.
public enum OpenRaster {
    /// Opens `.ora` bytes, decoding each layer's PNG with `pixels`.
    public static func read(_ data: Data, pixels: any PixelCodec) throws -> LayeredImage {
        throw CodecError.unsupported("not built")
    }

    /// Saves an image as `.ora` bytes, encoding each layer's PNG with `pixels`.
    /// `extra` holds app entries stored beside the standard ones, keyed by path
    /// (for example `photo/document.json`).
    public static func write(_ image: LayeredImage, pixels: any PixelCodec,
                             extra: [String: Data] = [:]) throws -> Data {
        throw CodecError.unsupported("not built")
    }
}
