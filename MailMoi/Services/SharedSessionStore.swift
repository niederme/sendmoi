import Foundation

enum SharedSessionStore {
    private static let key = "gmailSession"
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    static func load() throws -> GmailSession? {
        guard let data = SharedContainer.sharedDefaults.data(forKey: key) else {
            return nil
        }
        return try decoder.decode(GmailSession.self, from: data)
    }

    static func save(_ session: GmailSession) throws {
        let data = try encoder.encode(session)
        SharedContainer.sharedDefaults.set(data, forKey: key)
    }

    static func clear() {
        SharedContainer.sharedDefaults.removeObject(forKey: key)
    }
}
