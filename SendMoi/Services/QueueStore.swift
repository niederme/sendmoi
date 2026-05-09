import Foundation

enum QueueStore {
    private static let fileName = "queued-emails.json"
    static let didChangeNotification = "com.niederme.SendMoi.queueDidChange"

    static func load() throws -> [QueuedEmail] {
        let url = try queueFileURL()
        guard FileManager.default.fileExists(atPath: url.path()) else {
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
            queue.insert(item, at: 0)
            try save(queue)
        }
    }

    @discardableResult
    static func replace(_ item: QueuedEmail) throws -> Bool {
        var queue = try load()
        guard let index = queue.firstIndex(where: { $0.id == item.id }) else {
            return false
        }

        queue[index] = item
        try save(queue)
        return true
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
