import Foundation

enum QueueStore {
    private static let fileName = "queued-emails.json"
    static let didChangeNotification = "com.niederme.SendMoi.queueDidChange"

    static func load() throws -> [QueuedEmail] {
        let url = try queueFileURL()
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([QueuedEmail].self, from: data)
    }

    private static func save(_ queue: [QueuedEmail]) throws {
        let url = try queueFileURL()
        let data = try JSONEncoder().encode(queue)
        try data.write(to: url, options: .atomic)
        notifyQueueDidChange()
    }

    private static func append(_ item: QueuedEmail) throws {
        // Use an exclusive file lock so concurrent extension processes don't
        // overwrite each other's items during a simultaneous read-modify-write.
        try withExclusiveLock {
            var queue = try load()
            queue.insert(item, at: 0)
            try save(queue)
        }
    }

    /// Appends an item and claims it for the calling process for `leaseSeconds`.
    ///
    /// The share extension uses this to persist a share *before* it dismisses the
    /// sheet, so nothing is lost if the extension is terminated mid-delivery,
    /// while the lease keeps the main app from sending the same item in parallel.
    static func appendClaimed(_ item: QueuedEmail, leaseSeconds: TimeInterval) throws {
        var claimed = item
        claimed.leaseExpiresAt = Date().addingTimeInterval(leaseSeconds)
        try append(claimed)
    }

    /// Updates a claimed item's content (e.g. after preview enrichment) without
    /// disturbing its lease. No-op if the item is no longer queued.
    static func updateContentPreservingClaim(_ item: QueuedEmail) throws {
        try withExclusiveLock {
            var queue = try load()
            guard let index = queue.firstIndex(where: { $0.id == item.id }) else {
                return
            }

            var updated = item
            updated.leaseExpiresAt = queue[index].leaseExpiresAt
            queue[index] = updated
            try save(queue)
        }
    }

    static func remove(id: UUID) throws {
        try withExclusiveLock {
            var queue = try load()
            let remaining = queue.filter { $0.id != id }
            guard remaining.count != queue.count else {
                return
            }

            queue = remaining
            try save(queue)
        }
    }

    static func remove(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let removed = Set(ids)
        try withExclusiveLock {
            var queue = try load()
            let remaining = queue.filter { !removed.contains($0.id) }
            guard remaining.count != queue.count else {
                return
            }

            queue = remaining
            try save(queue)
        }
    }

    /// Releases the caller's claim on an item so the main app can retry it,
    /// recording why the in-flight attempt failed.
    static func releaseClaim(id: UUID, lastError: String?) throws {
        try withExclusiveLock {
            var queue = try load()
            guard let index = queue.firstIndex(where: { $0.id == id }) else {
                return
            }

            queue[index].leaseExpiresAt = nil
            if let lastError {
                queue[index].lastError = lastError
            }
            try save(queue)
        }
    }

    static func setLastError(id: UUID, message: String?) throws {
        try withExclusiveLock {
            var queue = try load()
            guard let index = queue.firstIndex(where: { $0.id == id }) else {
                return
            }

            queue[index].lastError = message
            try save(queue)
        }
    }

    private static func queueFileURL() throws -> URL {
        try SharedContainer.appDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
    }

    private static func lockFileURL() throws -> URL {
        try SharedContainer.appDirectoryURL().appendingPathComponent("queued-emails.lock", isDirectory: false)
    }

    /// Acquires an exclusive POSIX flock on a companion lock file, runs `work`,
    /// then releases the lock. Safe across processes sharing the same group
    /// container (the share extension and the main app).
    private static func withExclusiveLock(_ work: () throws -> Void) throws {
        let url = try lockFileURL()
        let fd = open(url.path, O_CREAT | O_RDWR, 0o666)
        guard fd != -1 else {
            // Can't obtain lock file — run unprotected rather than losing the item.
            try work()
            return
        }
        defer { close(fd) }
        flock(fd, LOCK_EX)          // blocks until the lock is available
        defer { flock(fd, LOCK_UN) }
        try work()
    }

    private static func notifyQueueDidChange() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: didChangeNotification as CFString),
            nil,
            nil,
            true
        )
    }
}
