import Foundation

struct GoodLinksSyncJob: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var excerpt: String
    var summary: String?
    var urlString: String
    var tags: [String]
    var starred: Bool
    var read: Bool
    var createdAt: Date
    var attemptCount: Int
    var lastError: String?

    init(item: QueuedEmail, settings: GoodLinksSettings) {
        id = item.id
        title = item.title
        excerpt = item.excerpt
        summary = item.summary
        urlString = item.urlString
        tags = settings.tags
        starred = settings.starred
        read = settings.read
        createdAt = .now
        attemptCount = 0
        lastError = nil
    }
}

enum GoodLinksSyncStore {
    static let didChangeNotification = "com.niederme.SendMoi.goodLinksSyncQueueDidChange"

    private static let queueKey = "goodLinks.syncedQueue.v1"
    private static let store = NSUbiquitousKeyValueStore.default

    static func load() -> [GoodLinksSyncJob] {
        store.synchronize()
        guard let data = store.data(forKey: queueKey),
              let queue = try? JSONDecoder().decode([GoodLinksSyncJob].self, from: data) else {
            return []
        }
        return queue
    }

    static func append(item: QueuedEmail, settings: GoodLinksSettings) throws {
        try append(GoodLinksSyncJob(item: item, settings: settings))
    }

    static func append(_ job: GoodLinksSyncJob) throws {
        var queue = load()
        if let index = queue.firstIndex(where: { $0.id == job.id || $0.urlString == job.urlString }) {
            queue[index] = job
        } else {
            queue.insert(job, at: 0)
        }
        try save(queue)
    }

    static func remove(id: UUID) throws {
        var queue = load()
        queue.removeAll { $0.id == id }
        try save(queue)
    }

    static func recordFailure(id: UUID, message: String) throws {
        var queue = load()
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].attemptCount += 1
        queue[index].lastError = message
        try save(queue)
    }

    private static func save(_ queue: [GoodLinksSyncJob]) throws {
        let data = try JSONEncoder().encode(queue)
        store.set(data, forKey: queueKey)
        store.synchronize()
        notifyQueueDidChange()
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

struct GoodLinksSyncDrainResult: Equatable {
    var savedCount: Int
    var remainingCount: Int
    var lastError: String?

    var didSaveJobs: Bool {
        savedCount > 0
    }
}

enum GoodLinksSyncProcessor {
    static func drain(using service: GoodLinksService = GoodLinksService()) async -> GoodLinksSyncDrainResult {
        let jobs = GoodLinksSyncStore.load()
        guard !jobs.isEmpty else {
            return GoodLinksSyncDrainResult(savedCount: 0, remainingCount: 0, lastError: nil)
        }

        let settings = GoodLinksSettingsStore.load()
        var savedCount = 0
        for job in jobs.reversed() {
            do {
                try await service.saveUsingLocalAPI(job: job, settings: settings)
                try GoodLinksSyncStore.remove(id: job.id)
                savedCount += 1
            } catch {
                try? GoodLinksSyncStore.recordFailure(id: job.id, message: error.localizedDescription)
                return GoodLinksSyncDrainResult(
                    savedCount: savedCount,
                    remainingCount: GoodLinksSyncStore.load().count,
                    lastError: error.localizedDescription
                )
            }
        }

        return GoodLinksSyncDrainResult(savedCount: savedCount, remainingCount: 0, lastError: nil)
    }
}
