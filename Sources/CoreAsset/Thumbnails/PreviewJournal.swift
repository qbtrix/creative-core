// PreviewJournal.swift: the index's append-only journal, so a write costs O(1)
// amortised index I/O: "FLPJ1:", the 16-hex generation of `index.json`, "\n",
// then a JSON `PreviewJournalRecord` per line. Invariants: it runs under the
// folder lock; past max(64, entries / 2) records it is compacted; a journal of
// another generation or an unfinished last line is ignored; a damaged line throws.
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

/// One journal line: `put` an entry, or `drop` a key.
struct PreviewJournalRecord: Codable, Sendable {
    var put: PreviewEntry?
    var drop: PreviewKey?
}

/// A store's view of its index, the journal bytes applied, and its index I/O.
struct PreviewLedger: Sendable {
    var entries: [PreviewKey: PreviewEntry] = [:]
    var generation = "", journalEnd = 0, journalRecords = 0, stale = false
    var bytesRead = 0, bytesWritten = 0, indexWrites = 0

    var needsCompaction: Bool { stale || journalRecords > max(64, entries.count / 2) }

    /// Applies `record`; a put keeps the later of its own and the held `lastRead`.
    mutating func apply(_ record: PreviewJournalRecord) throws(AssetError) {
        switch (record.put, record.drop) {
        case (var entry?, nil):
            guard (0...Int(UInt32.max)).contains(entry.byteCount) else { throw .invalid("the preview journal names an impossible size") }
            if let held = entries[entry.key], held.lastRead > entry.lastRead { entry.lastRead = held.lastRead }
            entries[entry.key] = entry
        case (nil, let key?): entries[key] = nil
        default: throw .invalid("the preview journal holds a damaged record")
        }
    }
}

extension PreviewFiles {
    var journal: URL { folder.appendingPathComponent("index.journal") }
    var damagedJournal: URL { folder.appendingPathComponent("index.damaged.journal") }

    static func journalHeader(_ generation: String) -> Data { Data(("FLPJ1:" + generation + "\n").utf8) }

    /// Applies the complete lines of `tail`, journal bytes from `ledger.journalEnd`.
    func replay(_ tail: Data, into ledger: inout PreviewLedger) throws(AssetError) {
        guard let last = tail.lastIndex(of: 0x0A) else { return }
        let array = Data([0x5B]) + Data(tail[tail.startIndex..<last].map { $0 == 0x0A ? 0x2C : $0 }) + Data([0x5D])
        let records: [PreviewJournalRecord]
        do { records = try JSONDecoder().decode([PreviewJournalRecord].self, from: array) } catch {
            throw .invalid("the preview journal is damaged")
        }
        for record in records { try ledger.apply(record) }
        ledger.journalEnd += last - tail.startIndex + 1
        ledger.journalRecords += records.count
    }

    /// Reads the journal past `ledger.journalEnd` into it; when another store
    /// compacted or it is damaged, reloads the index, keeping later reads.
    func catchUp(_ ledger: inout PreviewLedger) throws(AssetError) {
        if case let (header, tail)? = readJournal(from: ledger.journalEnd, ledger: &ledger),
           header == Self.journalHeader(ledger.generation) {
            do throws(AssetError) { return try replay(tail, into: &ledger) } catch {}
        }
        let held = ledger.entries
        try load(&ledger)
        for (key, mine) in held where ledger.entries[key].map({ $0.lastRead < mine.lastRead }) == true {
            ledger.entries[key]?.lastRead = mine.lastRead
        }
    }

    /// The journal's 23-byte header and its bytes from `offset`; nil when it is missing or short.
    func readJournal(from offset: Int, ledger: inout PreviewLedger) -> (Data, Data)? {
        let descriptor = open(journal.path, O_RDONLY)
        guard descriptor >= 0 else { return nil }
        defer { _ = close(descriptor) }
        var info = stat(), header = [UInt8](repeating: 0, count: 23)
        let start = max(offset, header.count)
        guard fstat(descriptor, &info) == 0, Int(info.st_size) >= start else { return nil }
        var tail = [UInt8](repeating: 0, count: Int(info.st_size) - start)
        guard Self.transfer(descriptor, &header, at: 0, write: false), Self.transfer(descriptor, &tail, at: start, write: false) else { return nil }
        ledger.bytesRead += header.count + tail.count
        return (Data(header), Data(tail))
    }

    /// Appends `records` at `ledger.journalEnd`, cutting off any unfinished line there.
    func append(_ records: [PreviewJournalRecord], to ledger: inout PreviewLedger) throws(AssetError) {
        var bytes: [UInt8] = []
        for record in records {
            do { bytes += try JSONEncoder().encode(record) + [0x0A] } catch { throw .invalid("cannot encode a preview journal record") }
        }
        let descriptor = open(journal.path, O_WRONLY)
        guard descriptor >= 0 else { throw .invalid("cannot open the preview journal") }
        defer { _ = close(descriptor) }
        guard ftruncate(descriptor, off_t(ledger.journalEnd)) == 0, Self.transfer(descriptor, &bytes, at: ledger.journalEnd, write: true) else {
            throw .invalid("cannot append to the preview journal")
        }
        ledger.journalEnd += bytes.count
        ledger.journalRecords += records.count
        ledger.bytesWritten += bytes.count
        ledger.indexWrites += 1
    }

    /// Writes the entries as a snapshot of a new generation, then an empty journal naming it.
    func compact(_ ledger: inout PreviewLedger, budgetBytes: Int) throws(AssetError) {
        let generation = String(UInt64.random(in: 1 << 60 ... .max), radix: 16)  // always 16 digits
        let header = Self.journalHeader(generation)
        ledger.bytesWritten += try saveIndex(ledger.entries, budgetBytes: budgetBytes, generation: generation)
        try replace(journal, with: header)
        (ledger.generation, ledger.journalEnd, ledger.journalRecords, ledger.stale) = (generation, header.count, 0, false)
        ledger.bytesWritten += header.count
        ledger.indexWrites += 2
    }

    /// Reads or writes all of `bytes` at `offset`; false on a failure.
    private static func transfer(_ descriptor: Int32, _ bytes: inout [UInt8], at offset: Int, write: Bool) -> Bool {
        var done = 0
        while done < bytes.count {
            let n = bytes.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                let at = off_t(offset + done)
                return write ? pwrite(descriptor, base + done, raw.count - done, at) : pread(descriptor, base + done, raw.count - done, at)
            }
            guard n > 0 else { return false }
            done += n
        }
        return true
    }
}
