import Foundation

enum QueueStore {
    private static let fileName = "queued-emails.json"

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
    }

    static func append(_ item: QueuedEmail) throws {
        var queue = try load()
        queue.insert(item, at: 0)
        try save(queue)
    }

    private static func queueFileURL() throws -> URL {
        try SharedContainer.appDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
    }
}
