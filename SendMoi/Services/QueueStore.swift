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

    static func save(_ queue: [QueuedEmail]) throws {
        let url = try queueFileURL()
        let data = try JSONEncoder().encode(queue)
        try data.write(to: url, options: .atomic)
        notifyQueueDidChange()
    }

    static func append(_ item: QueuedEmail) throws {
        // Use an exclusive file lock so concurrent extension processes don't
        // overwrite each other's items during a simultaneous read-modify-write.
        try withExclusiveLock {
            var queue = try load()
            guard !queue.contains(where: { $0.id == item.id }) else { return }
            queue.insert(item, at: 0)
            try save(queue)
        }
    }

    @discardableResult
    static func replace(_ item: QueuedEmail) throws -> Bool {
        try withExclusiveLock {
            var queue = try load()
            guard let index = queue.firstIndex(where: { $0.id == item.id }) else { return false }
            queue[index] = item
            try save(queue)
            return true
        }
    }

    static func remove(ids: [UUID]) throws {
        try withExclusiveLock {
            var queue = try load()
            queue.removeAll { ids.contains($0.id) }
            try save(queue)
        }
    }

    static func markFailure(id: UUID, message: String) throws {
        try withExclusiveLock {
            var queue = try load()
            guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
            // Do not notify observers on an unchanged error and create a retry loop.
            guard queue[index].lastError != message else { return }
            queue[index].lastError = message
            try save(queue)
        }
    }

    // Separate from the short mutation lock: held over delivery awaits, but acquired
    // non-blocking so a second process never blocks its main actor on a network send.
    static func acquireDeliveryLock() throws -> Int32? {
        let url = try SharedContainer.appDirectoryURL().appendingPathComponent("queue-delivery.lock")
        let fd = open(url.path, O_CREAT | O_RDWR, 0o600)
        guard fd != -1 else { throw POSIXError(.EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return fd
    }

    static func releaseDeliveryLock(_ fd: Int32) {
        flock(fd, LOCK_UN)
        close(fd)
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
    private static func withExclusiveLock<T>(_ work: () throws -> T) throws -> T {
        let url = try lockFileURL()
        let fd = open(url.path, O_CREAT | O_RDWR, 0o666)
        guard fd != -1 else {
            throw POSIXError(.EIO)
        }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(fd, LOCK_UN) }
        return try work()
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
