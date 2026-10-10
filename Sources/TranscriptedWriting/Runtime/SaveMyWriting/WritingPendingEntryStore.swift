import Foundation

/// Durable ownership of CLOSED, already scrubbed entries while the capture
/// library is unavailable. Never stores raw events, open text or scrubber
/// context. The bridge injects an app-state folder, independent of the library.
enum WritingPendingEntryStore {
    static let fileName = "pending-writing.json"
    static let maximumEntries = 256
    static let maximumBytes = 8 * 1_024 * 1_024

    struct Receipt: Codable, Equatable {
        let eventID: String
        let appBundleIdentifier: String
        let historyIdentifier: String
        let consentIdentifier: String
    }

    struct Snapshot: Codable {
        var version = 1
        var entries: [WritingEntryComposer.Entry] = []
        var receipts: [Receipt] = []
    }

    static func load(in directory: URL) throws -> Snapshot {
        let file = directory.appendingPathComponent(fileName)
        switch SecureLocalStorage.openExistingOwnerOnlyFileForReadOnlyStatus(at: file) {
        case .missing: return Snapshot()
        case .rejected: throw WritingDayFileStore.StoreError.pendingStoreUnavailable
        case let .opened(handle):
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: maximumBytes + 1),
                  data.count <= maximumBytes,
                  let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
                  snapshot.version == 1,
                  snapshot.entries.count <= maximumEntries,
                  snapshot.receipts.count <= 512 else {
                throw WritingDayFileStore.StoreError.pendingStoreUnavailable
            }
            return snapshot
        }
    }

    static func save(_ snapshot: Snapshot, in directory: URL) throws {
        guard snapshot.entries.count <= maximumEntries else {
            throw WritingDayFileStore.StoreError.pendingStoreFull
        }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= maximumBytes else { throw WritingDayFileStore.StoreError.pendingStoreFull }
        guard SecureLocalStorage.ensureOwnerOnlyDirectory(at: directory) else {
            throw WritingDayFileStore.StoreError.pendingStoreUnavailable
        }
        let temporary = directory.appendingPathComponent(".pending-writing-\(UUID().uuidString).tmp")
        let file = directory.appendingPathComponent(fileName)
        guard let handle = SecureLocalStorage.openFileForAppending(at: temporary) else {
            throw WritingDayFileStore.StoreError.pendingStoreUnavailable
        }
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            guard SecureLocalStorage.replaceOwnerOnlyFile(at: file, with: temporary),
                  SecureLocalStorage.synchronizeOwnerOnlyDirectory(at: directory) else {
                throw WritingDayFileStore.StoreError.pendingStoreUnavailable
            }
        } catch {
            try? handle.close()
            _ = SecureLocalStorage.removeOwnerOnlyFile(at: temporary)
            throw WritingDayFileStore.StoreError.pendingStoreUnavailable
        }
    }

    /// Temporary snapshots never acknowledged ownership. Once the published
    /// journal is loaded, discard them so a scope/consent change cannot leave
    /// an older private snapshot behind.
    static func removeInterruptedWrites(in directory: URL) -> Bool {
        var info = stat()
        if lstat(directory.path, &info) != 0 { return errno == ENOENT }
        guard info.st_mode & S_IFMT == S_IFDIR,
              SecureLocalStorage.ensureOwnerOnlyDirectory(at: directory),
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return false }
        var removed = true
        for name in names where name.hasPrefix(".pending-writing-") && name.hasSuffix(".tmp") {
            if !SecureLocalStorage.removeOwnerOnlyFile(at: directory.appendingPathComponent(name)) { removed = false }
        }
        return SecureLocalStorage.synchronizeOwnerOnlyDirectory(at: directory) && removed
    }

    /// Explicit privacy erase. Does not follow links or delete unrelated files.
    static func delete(in directory: URL) -> Bool {
        var info = stat()
        if lstat(directory.path, &info) != 0 { return errno == ENOENT }
        guard info.st_mode & S_IFMT == S_IFDIR,
              SecureLocalStorage.ensureOwnerOnlyDirectory(at: directory),
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return false }
        var deleted = true
        // An interrupted atomic write can leave a scrubbed temporary snapshot.
        // Privacy erase includes it even if the published journal is missing.
        for name in names where name == fileName || (name.hasPrefix(".pending-writing-") && name.hasSuffix(".tmp")) {
            if !SecureLocalStorage.removeOwnerOnlyFile(at: directory.appendingPathComponent(name)) { deleted = false }
        }
        return SecureLocalStorage.synchronizeOwnerOnlyDirectory(at: directory) && deleted
    }
}
