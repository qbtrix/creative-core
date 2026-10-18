// OpenRasterDeep.swift: 16-bit layers and the colour profile for OpenRaster
// (colour-profiles CP-8). The OpenRaster spec has no depth or profile field,
// so both ride on what a PNG and a zip already carry:
// - Depth. Every layer PNG and `mergedimage.png` is encoded at the image's
//   `bitsPerChannel` (8 or 16) through the injected `PixelCodec`; each PNG
//   records it in its IHDR bit depth (byte 24, PNG spec 11.2.2). The reader
//   reports 16 when any of them says 16, else 8.
// - Profile. `profile.icc` at the archive root holds `ColorProfile.iccData()`;
//   other readers ignore the unknown entry. The reader reads it back with
//   `ColorProfile(iccData:)` within `maxProfileBytes`, and an `extra` entry
//   may not use its path.
// An 8-bit image without a profile writes exactly the bytes it did before.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreColor

extension OpenRaster {
    /// The archive path of the embedded ICC profile.
    public static let profilePath = "profile.icc"
    /// The largest `profile.icc` read, as for `stack.xml`.
    public static let maxProfileBytes = StackXML.maxBytes

    /// 16 when any PNG in `paths` records bit depth 16 in its IHDR, else 8.
    /// `read` has checked each holds a PNG signature and IHDR; a header cut
    /// before the depth byte counts as 8.
    static func bitsPerChannel(_ entries: [String: Data], _ paths: [String]) -> Int {
        paths.contains { entries[$0].flatMap { $0.dropFirst(24).first } == 16 } ? 16 : 8
    }

    /// The `profile.icc` entry as a profile, nil without one. Throws `tooLarge`
    /// over `maxProfileBytes` and `damaged` for bytes ICC read refuses.
    static func profile(_ entries: [String: Data]) throws -> ColorProfile? {
        guard let bytes = entries[profilePath] else { return nil }
        guard bytes.count <= maxProfileBytes else { throw CodecError.tooLarge("\(profilePath) is \(bytes.count) bytes") }
        do { return try ColorProfile(iccData: bytes) } catch { throw CodecError.damaged("\(profilePath): \(error)") }
    }

    /// The depth every PNG is encoded at and the `profile.icc` bytes (nil
    /// without a profile), validated before anything is encoded: `unsupported`
    /// for a depth other than 8 or 16, a profile `iccData()` cannot write, or
    /// an `extra` entry at `profilePath`.
    static func depthAndProfile(_ image: LayeredImage, extra: [String: Data]) throws -> (bits: Int, icc: Data?) {
        guard image.bitsPerChannel == 8 || image.bitsPerChannel == 16 else {
            throw CodecError.unsupported("\(image.bitsPerChannel) bits per channel")
        }
        guard extra[profilePath] == nil else { throw CodecError.unsupported("extra entry \(profilePath) collides with a standard entry") }
        guard let profile = image.profile else { return (image.bitsPerChannel, nil) }
        do { return (image.bitsPerChannel, try profile.iccData()) } catch {
            throw CodecError.unsupported("the colour profile \"\(profile.name)\": \(error)")
        }
    }
}
