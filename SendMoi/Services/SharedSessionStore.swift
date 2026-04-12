import Foundation

enum SharedSessionStore {
    private static let fileName = "session.json"
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    static func load() throws -> GmailSession? {
        let url = try sessionFileURL()
        guard FileManager.default.fileExists(atPath: url.path()) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(GmailSession.self, from: data)
    }

    static func save(_ session: GmailSession) throws {
        let url = try sessionFileURL()
        let data = try encoder.encode(session)
        try data.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url = try? sessionFileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func sessionFileURL() throws -> URL {
        try SharedContainer.appDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
    }
}
