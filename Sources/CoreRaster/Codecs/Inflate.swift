// Inflate.swift: DEFLATE decompression (RFC 1951), bare or zlib-wrapped
// (RFC 1950), for PNG's IDAT stream. Stubs until IC-3, which keeps these
// signatures. Invariants: untrusted input throws `CodecError`, never traps;
// output past `limit` throws `tooLarge`, checked before the output grows.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// DEFLATE decompression, from the published RFCs only.
public enum Inflate {
    /// `data` as a zlib stream (a 2-byte header, DEFLATE blocks, a big-endian
    /// Adler-32 of the output), inflated to at most `limit` bytes.
    ///
    /// Throws `CodecError.damaged` on a bad header (method not 8, window over
    /// 32 KiB, failed check bits, a preset dictionary), a bad block, code or
    /// distance, early end of input, or a wrong Adler-32; `tooLarge` once the
    /// output would pass `limit`. Until IC-3 it throws `unsupported`.
    public static func zlib(_ data: Data, limit: Int) throws -> Data {
        throw CodecError.unsupported("zlib inflate waits on IC-3")
    }

    /// `data` as bare DEFLATE blocks (stored, fixed and dynamic Huffman), with
    /// no wrapper or checksum, inflated to at most `limit` bytes.
    ///
    /// Throws `CodecError.damaged` on a reserved block type, a stored length
    /// whose complement disagrees, an over-subscribed or incomplete code, a
    /// distance past the bytes written, or input that ends before the final
    /// block; `tooLarge` once the output would pass `limit`. Until IC-3 it
    /// throws `unsupported`.
    public static func raw(_ data: Data, limit: Int) throws -> Data {
        throw CodecError.unsupported("raw inflate waits on IC-3")
    }
}
