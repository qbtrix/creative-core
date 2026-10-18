// PreviewFiles.swift: the preview store's layout on disk. `folder/index.json`
// lists the entries; each preview is `folder/p/<2 hex>/<16 hex>.bin`, named by a
// 64-bit FNV-1a of its key so no user text reaches a path, and holds "FLPV", a
// version byte, a 4-byte big-endian length, that much JSON `PreviewFileHeader`,
// then the payload, so the index can be rebuilt from the files (PreviewIndex.swift).
// Invariants: a file is replaced by writing `<name>.tmp` whole and renaming it
// over the old, and every change runs under an exclusive `flock` on
// `folder/lock`; a header that is short, unknown or runs past its file throws
// `AssetError`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// What a preview file says about itself ahead of its payload.
struct PreviewFileHeader: Codable, Sendable {
    var key: PreviewKey
    var volume: VolumeRef?
    var relativePath: String?
}

/// The files of one preview store's folder.
struct PreviewFiles: Sendable {
    let folder: URL

    var index: URL { folder.appendingPathComponent("index.json") }
    private var lockFile: URL { folder.appendingPathComponent("lock") }
    var previews: URL { folder.appendingPathComponent("p", isDirectory: true) }

    /// Creates the folder and its preview directory when they are missing.
    func createFolders() throws(AssetError) {
        do { try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true) } catch {
            throw .invalid("cannot create the preview folder \(folder.path)")
        }
    }

    /// The preview file for `key`.
    func file(for key: PreviewKey) -> URL {
        previews.appendingPathComponent(Self.name(for: key))
    }

    /// `key`'s file under `p/`: `<2 hex>/<16 hex>.bin`, the lowercase hex of its digest.
    static func name(for key: PreviewKey) -> String {
        let digits = String(digest(key), radix: 16)
        let name = String(repeating: "0", count: 16 - digits.count) + digits
        return String(name.prefix(2)) + "/" + name + ".bin"
    }

    /// A stable 64-bit FNV-1a over the key's fields, each ended by a zero byte.
    static func digest(_ key: PreviewKey) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in [key.asset, key.content, String(key.size.rawValue)].flatMap({ (field: String) -> [UInt8] in Array(field.utf8) + [0] }) {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    static let magic = Array("FLPV".utf8)
    static let headerVersion: UInt8 = 1

    /// A preview file's bytes: the header, then `payload`.
    static func encode(_ header: PreviewFileHeader, payload: Data) throws(AssetError) -> Data {
        let json: Data
        do { json = try JSONEncoder().encode(header) } catch { throw .invalid("cannot encode a preview header") }
        guard let length = UInt32(exactly: json.count) else { throw .invalid("a preview header is too long") }
        let prefix = magic + [headerVersion] + (0..<4).map { UInt8(truncatingIfNeeded: length >> (24 - 8 * $0)) }
        return Data(prefix) + json + payload
    }

    /// The header and payload of a preview file's bytes.
    static func decode(_ data: Data) throws(AssetError) -> (PreviewFileHeader, Data) {
        let fixed = magic.count + 5
        let start = data.startIndex
        guard data.count >= fixed, data.prefix(magic.count).elementsEqual(magic) else { throw .invalid("not a preview file") }
        guard data[start + magic.count] == headerVersion else { throw .invalid("preview file version is not supported") }
        let length = data[(start + magic.count + 1)..<(start + fixed)].reduce(0) { $0 << 8 | Int($1) }
        guard length >= 0, length <= data.count - fixed else { throw .invalid("a preview header runs past its file") }
        let json = Data(data[(start + fixed)..<(start + fixed + length)])
        do { return (try JSONDecoder().decode(PreviewFileHeader.self, from: json), Data(data[(start + fixed + length)...])) } catch {
            throw .invalid("a preview header is damaged")
        }
    }

    /// Replaces `file` with `data`: the bytes go to `<file>.tmp`, which is
    /// renamed over `file` only once it is complete.
    func replace(_ file: URL, with data: Data) throws(AssetError) {
        let temp = URL(fileURLWithPath: file.path + ".tmp")
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: temp)
        } catch {
            throw .invalid("cannot write preview file \(temp.lastPathComponent)")
        }
        guard rename(temp.path, file.path) == 0 else { throw .invalid("cannot replace preview file \(file.lastPathComponent)") }
    }

    /// Runs `body` holding the folder's exclusive lock.
    func withLock<T>(_ body: () throws(AssetError) -> T) throws(AssetError) -> T {
        let descriptor = open(lockFile.path, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else { throw .invalid("cannot open the preview lock") }
        defer { _ = close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw .invalid("cannot lock the preview folder") }
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }

    /// Deletes the preview file for `key`; one already gone is no error.
    func removeFile(for key: PreviewKey) {
        try? FileManager.default.removeItem(at: file(for: key))
    }
}
