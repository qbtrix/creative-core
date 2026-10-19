import CoreRaster
import Testing
import Foundation
@Suite struct ZZBench {
    @Test func bench() throws {
        var s: UInt64 = 1
        var bytes = [UInt8](repeating: 0, count: 48_000_000)
        for i in 0..<bytes.count { s = s &* 6364136223846793005 &+ 1442695040888963407; bytes[i] = (i % 7 == 0) ? UInt8(truncatingIfNeeded: s >> 60) : UInt8(truncatingIfNeeded: i / 3) }
        let d = Data(bytes)
        var t = Date()
        let z = Deflate.zlib(d, level: 6)
        print("deflate", Date().timeIntervalSince(t), z.count)
        t = Date()
        let back = try Inflate.zlib(z, limit: d.count)
        print("inflate", Date().timeIntervalSince(t), back == d)
        let st = Deflate.zlib(d, level: 0); t = Date()
        _ = try Inflate.zlib(st, limit: d.count)
        print("stored inflate", Date().timeIntervalSince(t))
    }
}
