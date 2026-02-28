import Foundation

enum RecipientStore {
    private static let historyKey = "savedRecipients"
    private static let defaultKey = "defaultRecipient"
    private static let maxCount = 12

    static func load() -> [String] {
        let values = SharedContainer.sharedDefaults.array(forKey: historyKey) as? [String] ?? []
        return values
    }

    static func loadDefault() -> String {
        SharedContainer.sharedDefaults.string(forKey: defaultKey) ?? ""
    }

    static func setDefault(_ recipient: String) {
        let normalized = normalize(recipient)
        SharedContainer.sharedDefaults.set(normalized, forKey: defaultKey)
        guard !normalized.isEmpty else {
            return
        }
        record(normalized)
    }

    static func record(_ recipient: String) {
        let normalized = normalize(recipient)
        guard !normalized.isEmpty else {
            return
        }

        var current = load().filter { $0 != normalized }
        current.insert(normalized, at: 0)
        current = Array(current.prefix(maxCount))
        SharedContainer.sharedDefaults.set(current, forKey: historyKey)
    }

    private static func normalize(_ recipient: String) -> String {
        recipient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
