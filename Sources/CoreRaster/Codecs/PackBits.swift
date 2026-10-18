// PackBits.swift: the byte-oriented run-length scheme PSD uses for RLE
// channel rows, from the published PackBits description. Each packet starts
// with a signed header byte n: 0...127 copies the next n + 1 bytes literally,
// -127...-1 repeats the next byte 1 - n times, and -128 is a no-op. Decoding
// knows the row's length and throws `CodecError.damaged` when a packet would
// write past it or the input ends first; it never traps on untrusted bytes.
enum PackBits {
    /// Decodes packets from `reader` until exactly `count` bytes are out.
    static func decode(_ reader: inout ByteReader, count: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(max(count, 0))
        while out.count < count {
            let header = Int(try reader.i8())
            if header >= 0 {
                let literal = header + 1
                try checkFits(literal, written: out.count, count: count)
                out.append(contentsOf: try reader.bytes(literal))
            } else if header != -128 {
                let run = 1 - header
                try checkFits(run, written: out.count, count: count)
                out.append(contentsOf: repeatElement(try reader.u8(), count: run))
            }
        }
        return out
    }

    /// Decodes one encoded row of `count` bytes.
    static func decode(_ bytes: [UInt8], count: Int) throws -> [UInt8] {
        var reader = ByteReader(bytes)
        return try decode(&reader, count: count)
    }

    private static func checkFits(_ length: Int, written: Int, count: Int) throws {
        guard length <= count - written else {
            throw CodecError.damaged("a run of \(length) passes the row end at \(written) of \(count)")
        }
    }

    /// Encodes `bytes`: runs of three or more equal bytes as repeat packets,
    /// everything else as literal packets, each at most 128 bytes long.
    static func encode(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var index = 0
        while index < bytes.count {
            let value = bytes[index]
            var run = 1
            while index + run < bytes.count, run < 128, bytes[index + run] == value { run += 1 }
            if run >= 3 {
                out.append(UInt8(truncatingIfNeeded: 1 - run))
                out.append(value)
                index += run
                continue
            }
            let start = index
            while index < bytes.count, index - start < 128 {
                if index + 2 < bytes.count, bytes[index] == bytes[index + 1], bytes[index] == bytes[index + 2] {
                    break
                }
                index += 1
            }
            out.append(UInt8(truncatingIfNeeded: index - start - 1))
            out.append(contentsOf: bytes[start..<index])
        }
        return out
    }
}
